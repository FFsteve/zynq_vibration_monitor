"""在线保存串口原始数据，或离线重放 FPGA 仿真捕获；无需绘图依赖。"""

import argparse
import csv
import json
from pathlib import Path
import time

from protocol import Sample, StreamDecoder


class CaptureLogs:
    def __init__(self, output: Path, mode="frame", keep_samples=False):
        if mode not in ("frame", "ack"):
            raise ValueError("模式必须为 frame 或 ack")
        output.mkdir(parents=True, exist_ok=True)
        if any((output / name).exists() for name in ("capture.bin", "samples.csv", "stats.json")):
            raise FileExistsError("输出目录已有记录，请使用新的目录，避免覆盖证据")
        self.output, self.mode = output, mode
        self.raw = (output / "capture.bin").open("xb")
        self.csv_file = (output / "samples.csv").open("x", newline="", encoding="utf-8")
        self.writer = csv.writer(self.csv_file)
        self.writer.writerow(("sample_index", "host_time_ns", "seq", "x", "y", "z"))
        self.decoder = StreamDecoder()
        self.samples = []
        self.keep_samples = keep_samples
        self.logged_frames = 0
        self.bytes = self.acks = self.unexpected_ack_bytes = 0

    def feed(self, chunk, host_time_ns=None):
        self.raw.write(chunk)
        self.bytes += len(chunk)
        if self.mode == "ack":
            self.acks += chunk.count(6)
            self.unexpected_ack_bytes += len(chunk) - chunk.count(6)
            return
        stamp = time.time_ns() if host_time_ns is None else host_time_ns
        for sample in self.decoder.feed(chunk):
            if self.keep_samples:
                self.samples.append(sample)
            self.writer.writerow((self.logged_frames, stamp, sample.seq, sample.x, sample.y, sample.z))
            self.logged_frames += 1

    def close(self):
        self.raw.close()
        self.csv_file.close()
        stats = {"mode": self.mode, "bytes": self.bytes, "ack_count": self.acks,
                 "unexpected_ack_bytes": self.unexpected_ack_bytes, **self.decoder.stats()}
        (self.output / "stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        return stats


def read_expected(path):
    with Path(path).open(newline="", encoding="utf-8") as f:
        return [Sample(*(int(row[key]) for key in ("seq", "x", "y", "z"))) for row in csv.DictReader(f)]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--input-bin", type=Path, help="离线二进制输入")
    source.add_argument("--port", help="在线串口，例如 COM5；本工具只接收，不向板卡发送")
    parser.add_argument("--mode", choices=("frame", "ack"), default="frame")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=10.0)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-csv", type=Path, help="离线验收的独立期望样本")
    parser.add_argument("--expect-count", type=int)
    args = parser.parse_args(argv)
    if args.seconds <= 0 or args.baud <= 0:
        parser.error("seconds 和 baud 必须为正")
    logs = None
    try:
        # 仅在线分支依赖 pyserial；离线复现与单元测试完全使用标准库。
        if args.port:
            import serial
        logs = CaptureLogs(args.output, args.mode, keep_samples=bool(args.expected_csv))
        try:
            if args.input_bin:
                with args.input_bin.open("rb") as f:
                    while True:
                        chunk = f.read(64)
                        if not chunk:
                            break
                        logs.feed(chunk, host_time_ns=0)
            else:
                with serial.Serial(args.port, args.baud, timeout=0.1, xonxoff=False, rtscts=False, dsrdtr=False) as port:
                    deadline = time.monotonic() + args.seconds
                    while time.monotonic() < deadline:
                        chunk = port.read(4096)
                        if chunk:
                            logs.feed(chunk)
        except KeyboardInterrupt:
            pass
        finally:
            stats = logs.close()
        count = stats["frames"] if args.mode == "frame" else stats["ack_count"]
        if args.expect_count is not None and count != args.expect_count:
            raise ValueError(f"数量错误：期望 {args.expect_count}，实际 {count}")
        if args.expected_csv:
            expected = read_expected(args.expected_csv)
            if args.mode == "frame" and logs.samples != expected:
                raise ValueError("解码样本与独立期望不一致")
            if args.mode == "ack" and count != len(expected):
                raise ValueError("ACK 数量与期望样本数不一致")
        if args.mode == "ack" and stats["unexpected_ack_bytes"]:
            raise ValueError("ACK 模式出现非 06 字节")
        print(json.dumps(stats, ensure_ascii=False))
        print(f"PASS capture mode={args.mode} count={count}")
        return 0
    except (OSError, ValueError, ImportError) as exc:
        print(f"FAIL capture: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
