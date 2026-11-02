"""从包内真实UART解码记录重新计算FIR参考，比较全部完整回包，不依赖旧build目录。"""
import csv
import gzip
import hashlib
import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "report/evidence"))
import analyze_session_20261101 as parser
from host.stage4_reference import dc_fixed, fir_fixed, round_away, saturate
import numpy as np


def main():
    base = ROOT / "data/measured/filter_test_3"
    identity = json.loads((base / "source_identity.json").read_text(encoding="utf-8"))
    for name, expected in identity["files"].items():
        if hashlib.sha256((base / name).read_bytes()).hexdigest() != expected:
            raise ValueError("实测输入身份不符：" + name)
    with tempfile.TemporaryDirectory() as folder:
        capture_root = Path(folder)
        for name, expected in identity["uncompressed_files"].items():
            data = gzip.decompress((base / (name + ".gz")).read_bytes())
            assert hashlib.sha256(data).hexdigest() == expected
            (capture_root / name).write_bytes(data)
        parser.BASE = capture_root
        incoming, outgoing = parser.uart("uart_d0.csv"), parser.uart("uart_d1.csv")
    for capture in [incoming, outgoing]:
        if any(capture[key] for key in ["warnings", "byte_issues", "bad_checksums", "gaps"]):
            raise ValueError("完整UART区间存在错误")
    inputs, replies = incoming["frames"], outgoing["frames"]
    assert len(inputs) == 4915 and len(replies) == 4914
    assert inputs[0]["seq"] == replies[0]["seq"] == 0 and inputs[0]["time"] > 0.012
    assert outgoing["oracle"]["trailing_bytes"] == 6
    coeff = [int(s, 16) for s in (ROOT / "data/reference/stage4/fir_lp_63_q16.mem").read_text().split()]
    coeff = [value - (1 << 18) if value & (1 << 17) else value for value in coeff]
    assert len(coeff) == 63 and sum(coeff) == 65536
    internal = []
    for axis in range(3):
        dc = dc_fixed([frame["axes"][axis] for frame in inputs])
        golden, _ = fir_fixed(dc, coeff)
        independent = np.convolve(np.asarray(dc, dtype=np.int64), np.asarray(coeff, dtype=np.int64))[:len(dc)]
        assert golden == [saturate(round_away(int(value), 16), 18) for value in independent]
        internal.append(golden)
    for index, reply in enumerate(replies):
        assert reply["seq"] == inputs[index]["seq"]
        assert reply["axes"] == [internal[axis][index] >> 2 for axis in range(3)], index
    result = dict(status="PASS_MEASURED_FILTER_REPLAY", input_frames=len(inputs),
                  complete_replies=len(replies), axes=3, mismatches=0,
                  boundary_trailing_bytes=6, initial_state="首包前静默超过12ms",
                  evidence_kind="真实UART导出重新解码与独立整数/卷积参考对照",
                  physical_buzzer_retested=False)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()

