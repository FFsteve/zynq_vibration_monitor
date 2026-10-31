"""独立检查本次由 ATK-Logic 界面导出的协议 CSV；不操作硬件。"""

import csv
import hashlib
import io
import json
import math
import re
import statistics
import sys
import zipfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from host.protocol import decode

BASE = Path(__file__).resolve().parent


def time_us(value):
    number, unit = value.split()
    return float(number) * {"ns": 0.001, "μs": 1, "us": 1, "ms": 1000, "s": 1e6}[unit]


def read_rows(channel):
    raw = (BASE / f"sensor_source_{channel}_20261030.csv").read_bytes()
    # 厂商导出为 GB18030；保持原文件字节，不改写证据编码。
    rows = list(csv.reader(io.StringIO(raw.decode("gb18030"))))[1:]
    return [dict(index=int(r[0]), start=time_us(r[1]), duration=time_us(r[2]),
                 kind=r[3], value=r[4]) for r in rows if len(r) >= 5]


def uart(channel):
    rows = read_rows(channel)
    data = [r for r in rows if r["kind"] == "TX data" and re.fullmatch(r"[0-9A-Fa-f]{2}", r["value"])]
    frames, errors, skipped = [], [], []
    i = 0
    while i < len(data):
        if i + 10 <= len(data) and [r["value"].upper() for r in data[i:i+2]] == ["A5", "5A"]:
            block = data[i:i+10]
            packet = bytes(int(r["value"], 16) for r in block)
            try:
                sample = decode(packet)
            except ValueError as error:
                errors.append(dict(byte_offset=i, error=str(error)))
            else:
                # 解码器数据标记从首个数据位开始，减去该字节起始位宽。
                starts = [r for r in rows if r["kind"] == "TX data" and r["value"] == "Start bit"
                          and 0 < block[0]["start"] - r["start"] < 10]
                assert len(starts) == 1
                stops = [r for r in rows if r["kind"] == "TX data" and r["value"] == "Stop bit"
                         and abs(r["start"] - block[-1]["start"] - block[-1]["duration"]) < 0.06]
                assert len(stops) == 1
                frames.append(dict(seq=sample.seq, axes=[sample.x, sample.y, sample.z],
                                   hex=packet.hex(" ").upper(), payload=packet[3:9].hex(" ").upper(),
                                   start_us=starts[0]["start"],
                                   end_us=stops[0]["start"] + stops[0]["duration"]))
                i += 10
                continue
        skipped.append(data[i])
        i += 1
    discontinuities = [(a["seq"], b["seq"]) for a, b in zip(frames, frames[1:])
                       if b["seq"] != (a["seq"] + 1) % 256]
    intervals = [b["start_us"] - a["start_us"] for a, b in zip(frames, frames[1:])]
    unexpected = [r for r in rows if r["kind"] not in ("TX data", "TX bits")
                  or (r["kind"] == "TX data" and not re.fullmatch(r"[0-9A-Fa-f]{2}|Start bit|Stop bit", r["value"]))]
    assert sum(r["kind"] == "TX bits" for r in rows) == len(data)*8
    for marker in ["Start bit", "Stop bit"]:
        assert sum(r["kind"] == "TX data" and r["value"] == marker for r in rows) == len(data)
    return dict(bytes=len(data), frames=frames, checksum_errors=errors, discontinuities=discontinuities,
                boundary_bytes=skipped, unexpected=unexpected,
                intervals_us=intervals,
                mean_interval_us=statistics.mean(intervals) if intervals else None)


def main():
    d0, d1 = uart("d0"), uart("d1")
    rows = read_rows("i2c")
    transactions = []
    for n, row in enumerate(rows):
        if row["kind"] != "Packets":
            continue
        match = re.fullmatch(r"0x68 WR: ([0-9A-F]{2}) \[SR\] 0x68 RD: ([0-9A-F ]+)", row["value"])
        assert match, row
        start = row["start"]
        end = start + row["duration"]
        detail = [r for r in rows[:n] if r["kind"] == "Address/data" and start <= r["start"] < end]
        values = [r["value"] for r in detail]
        read_data = bytes.fromhex(match[2])
        expected = ["Address write: 68", "Write", "ACK", "Data write: " + match[1], "ACK",
                    "Address read: 68", "Read", "ACK"]
        for i, byte in enumerate(read_data):
            expected.extend([f"Data read: {byte:02X}", "NACK" if i == len(read_data)-1 else "ACK"])
        assert values == expected, (row, values)
        transactions.append(dict(start_us=start, end_us=end, register=match[1],
                                 payload=read_data.hex(" ").upper(), ack_pattern_ok=True))
    bursts = [t for t in transactions if t["register"] == "3B"]
    matches = []
    for frame in d0["frames"]:
        candidates = [t for t in bursts if t["end_us"] <= frame["start_us"] and frame["start_us"]-t["end_us"] < 100]
        assert len(candidates) == 1, frame
        transaction = candidates[0]
        assert frame["payload"] == transaction["payload"], (frame, transaction)
        replies = [r for r in d1["frames"] if r["seq"] == frame["seq"]]
        assert len(replies) == 1 and replies[0]["hex"] == frame["hex"], (frame, replies)
        matches.append(dict(seq=frame["seq"], i2c_end_us=transaction["end_us"],
                            d0_start_us=frame["start_us"], d1_start_us=replies[0]["start_us"],
                            sensor_to_uart_us=frame["start_us"]-transaction["end_us"],
                            uart_start_to_reply_us=replies[0]["start_us"]-frame["start_us"],
                            all_bytes_equal=True))
    assert len(matches) == len(bursts) == len(d0["frames"]) > 0
    assert not any(d0[k] or d1[k] for k in ["checksum_errors", "discontinuities", "unexpected"])
    # 第一包输入在捕获左边界截断；用相同尾部和时序确认额外回包的边界来源。
    extra = [r for r in d1["frames"] if r["seq"] not in {f["seq"] for f in d0["frames"]}]
    assert len(extra) == 1 and d0["boundary_bytes"]
    tail = " ".join(r["value"].upper() for r in d0["boundary_bytes"])
    assert extra[0]["hex"].endswith(tail)
    assert extra[0]["seq"] == (d0["frames"][0]["seq"]-1) % 256
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(BASE.glob("sensor_source_*20261030.*")) if p.suffix in (".csv", ".atkdl")}
    with zipfile.ZipFile(BASE / "sensor_source_20261030.atkdl") as archive:
        assert archive.testzip() is None
        assert all(f"{i}/0-0.bin" in archive.namelist() for i in range(4))
    last_end = transactions[-1]["end_us"]
    partial = [r for r in rows if r["kind"] == "Address/data" and r["start"] > last_end]
    axes = [f["axes"] for f in d0["frames"]]
    norms = [math.sqrt(sum(v*v for v in sample)) for sample in axes]
    stationary_review = dict(user_report="完全静止平放", expected_accel_config="源码 1C=00；本记录未捕获配置回读",
                             source="docs/hardware/mpu6050_module_manual.pdf 第7页：AFS_SEL=0，16384 LSB/g",
                             mean_axes=[statistics.mean(a[i] for a in axes) for i in range(3)],
                             mean_norm_counts=statistics.mean(norms),
                             mean_norm_g_if_2g_config=statistics.mean(norms)/16384,
                             conclusion="静止合成值偏离1g，测量值验收未通过，需补初始化及翻转验证；未确定根因")
    output = dict(scope="已有50ms稳态采集；通信对照通过，初始化与计量验收仍待完成", hashes=hashes,
                  d0=d0, d1=d1, i2c=transactions, register_counts=dict(Counter(t["register"] for t in transactions)),
                  comparisons=matches, initial_boundary_reply=extra, trailing_partial_i2c=partial,
                  archive_crc_ok=True, stationary_review=stationary_review,
                  result="PASS_COMMUNICATION_CAPTURE_MEASUREMENT_PENDING")
    (BASE / "sensor_source_analysis_20261030.json").write_text(json.dumps(output, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(dict(result=output["result"], d0_frames=len(d0["frames"]), d1_frames=len(d1["frames"]),
                          matching_chains=len(matches), register_counts=output["register_counts"],
                          d0_intervals_us=d0["intervals_us"], stationary_review=stationary_review,
                          archive_crc_ok=True), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
