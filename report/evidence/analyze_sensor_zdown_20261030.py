"""核对 Z 朝下采集，并与前次静止数据作条件性的两姿态比较。"""

import csv
import hashlib
import io
import json
import math
import re
import statistics
import zipfile
from collections import Counter
from pathlib import Path

import analyze_sensor_capture_20261030 as common

BASE = Path(__file__).resolve().parent


def read_rows(channel):
    raw = (BASE / f"sensor_zdown_{channel}_20261030.csv").read_bytes()
    return [dict(index=int(r[0]), start=common.time_us(r[1]), duration=common.time_us(r[2]),
                 kind=r[3], value=r[4])
            for r in list(csv.reader(io.StringIO(raw.decode("gb18030"))))[1:] if len(r) >= 5]


def main():
    original = {n: read_rows(n) for n in ["d0", "d1", "i2c"]}
    prefixes, usable = {}, {}
    for n in ["d0", "d1"]:
        rows = original[n]
        # 仅隔离首个 A5 前的窗口边界；所有被隔离记录仍写入结果，不隐藏警告。
        first_a5 = next(r for r in rows if r["kind"] == "TX data" and r["value"] == "A5")
        first_start = [r for r in rows if r["value"] == "Start bit" and 0 < first_a5["start"]-r["start"] < 10]
        assert len(first_start) == 1
        cutoff = first_start[0]["index"]
        prefixes[n] = [r for r in rows if r["index"] < cutoff]
        usable[n] = [r for r in rows if r["index"] >= cutoff]
    # 复用前次逐字节协议、位数、起停标记核查；不改动此前证据文件。
    common.read_rows = lambda channel: usable[channel]
    d0, d1 = common.uart("d0"), common.uart("d1")
    assert not any(d0[k] or d1[k] for k in ["checksum_errors", "discontinuities", "unexpected", "boundary_bytes"])
    assert len(d0["frames"]) == len(d1["frames"]) > 0
    transactions = []
    rows = original["i2c"]
    for i, r in enumerate(rows):
        if r["kind"] != "Packets":
            continue
        match = re.fullmatch(r"0x68 WR: ([0-9A-F]{2}) \[SR\] 0x68 RD: ([0-9A-F ]+)", r["value"])
        assert match, r
        payload = bytes.fromhex(match[2])
        detail = [x["value"] for x in rows[:i] if x["kind"] == "Address/data"
                  and r["start"] <= x["start"] < r["start"]+r["duration"]]
        expected = ["Address write: 68", "Write", "ACK", "Data write: "+match[1], "ACK",
                    "Address read: 68", "Read", "ACK"]
        for j, byte in enumerate(payload):
            expected += [f"Data read: {byte:02X}", "NACK" if j == len(payload)-1 else "ACK"]
        assert detail == expected, (r, detail)
        transactions.append(dict(start_us=r["start"], end_us=r["start"]+r["duration"],
                                 register=match[1], payload=payload.hex(" ").upper(), ack_pattern_ok=True))
    bursts = [r for r in transactions if r["register"] == "3B"]
    comparisons = []
    for frame, reply in zip(d0["frames"], d1["frames"]):
        assert frame["hex"] == reply["hex"]
        readings = [r for r in bursts if 0 <= frame["start_us"]-r["end_us"] < 100]
        assert len(readings) == 1 and readings[0]["payload"] == frame["payload"]
        comparisons.append(dict(seq=frame["seq"], i2c_end_us=readings[0]["end_us"],
                                d0_start_us=frame["start_us"], d1_start_us=reply["start_us"],
                                all_bytes_equal=True))
    assert len(bursts) == len(comparisons)
    previous_path = BASE / "sensor_source_analysis_20261030.json"
    previous = json.loads(previous_path.read_text(encoding="utf-8"))
    old_mean = previous["stationary_review"]["mean_axes"]
    new_mean = [statistics.mean(f["axes"][i] for f in d0["frames"]) for i in range(3)]
    midpoint = (old_mean[2]+new_mean[2])/2
    halfspan = (old_mean[2]-new_mean[2])/2
    norms = [math.sqrt(sum(v*v for v in f["axes"])) for f in d0["frames"]]
    warning_rows = [r for r in original["d1"] if "warning" in r["kind"].lower()]
    assert all(r in prefixes["d1"] for r in warning_rows)
    archive_path = BASE / "sensor_zdown_20261030.atkdl"
    with zipfile.ZipFile(archive_path) as archive:
        assert archive.testzip() is None
        assert all(f"{i}/0-0.bin" in archive.namelist() for i in range(4))
    evidence = [BASE / f"sensor_zdown_{n}_20261030.csv" for n in ["d0", "d1", "i2c"]]
    evidence += [archive_path, previous_path]
    output = dict(result="PASS_COMPLETE_CHAINS_BIAS_HYPOTHESIS_PENDING", capture_ms=50,
                  configuration_comparison="用户确认仅翻转、程序配置未改；实际配置回读仍未捕获。Z近似正反水平时，中点/半差才可解释为零偏/灵敏度初估",
                  d0=d0, d1=d1, i2c=transactions, comparisons=comparisons,
                  boundary_prefix=prefixes, boundary_warnings=warning_rows,
                  register_counts=dict(Counter(r["register"] for r in transactions)),
                  old_mean_axes=old_mean, new_mean_axes=new_mean,
                  mean_norm_g_if_2g_config=statistics.mean(norms)/16384,
                  provisional_z_offset_counts=midpoint, provisional_z_sensitivity_counts_per_g=halfspan,
                  provisional_scale_relative_error_percent=(halfspan/16384-1)*100,
                  provisional_z_offset_g=midpoint/16384,
                  archive_crc_ok=True, hashes={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in evidence})
    out_path = BASE / "sensor_zdown_analysis_20261030.json"
    out_path.write_text(json.dumps(output, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({k: output[k] for k in ["result", "register_counts", "old_mean_axes", "new_mean_axes",
                     "mean_norm_g_if_2g_config", "provisional_z_offset_counts", "provisional_z_sensitivity_counts_per_g",
                     "provisional_scale_relative_error_percent", "boundary_warnings"]}, ensure_ascii=False, indent=2))
    print("D0/D1 complete frames:", len(d0["frames"]), len(d1["frames"]))
    print("D0 intervals us:", d0["intervals_us"])


if __name__ == "__main__":
    main()
