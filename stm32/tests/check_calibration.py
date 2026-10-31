"""以独立浮点公式和有理数舍入核查实际C输出，不连接硬件。"""
import argparse
from fractions import Fraction
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "host"))
from protocol import decode


def round_away(value):
    magnitude = abs(value)
    result = (2 * magnitude.numerator + magnitude.denominator) // (2 * magnitude.denominator)
    return result if value >= 0 else -result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--analysis", type=Path, required=True)
    parser.add_argument("--vectors", type=Path, required=True)
    args = parser.parse_args()
    analysis = json.loads(args.analysis.read_text(encoding="utf-8"))
    bias, sensitivity = analysis["bias_counts"], analysis["sensitivity_counts_per_g"]
    biases, gains = analysis["bias_q16"], analysis["gain_q16"]
    data = args.vectors.read_bytes()
    assert len(data) == 65536 * 11
    max_difference, saturations = [0, 0, 0], [0, 0, 0]
    previous = [-32769] * 3
    for index, value in enumerate(range(-32768, 32768)):
        record = data[index * 11:(index + 1) * 11]
        sample = decode(record[:10])
        assert sample.seq == value % 256
        mask = 0
        for axis, actual in enumerate((sample.x, sample.y, sample.z)):
            # 精确有理数作为定点参考，避免复用C的整数操作顺序。
            exact = (Fraction(value) - Fraction(biases[axis], 65536)) * Fraction(gains[axis], 65536)
            expected = round_away(exact)
            if expected < -32768 or expected > 32767:
                mask |= 1 << axis
                saturations[axis] += 1
            expected = max(-32768, min(32767, expected))
            assert actual == expected, (axis, value, actual, expected)
            assert actual >= previous[axis]
            previous[axis] = actual
            ideal = round_away(Fraction((value - bias[axis]) * 16384 / sensitivity[axis]))
            ideal = max(-32768, min(32767, ideal))
            difference = abs(actual - ideal)
            max_difference[axis] = max(max_difference[axis], difference)
            assert difference <= 1, (axis, value, difference)
        assert record[10] == mask
    print("PASS calibration_crosscheck " + json.dumps({"axis_values": 196608, "packets": 65536,
          "max_integer_difference_from_float": max_difference, "saturations": saturations}))


if __name__ == "__main__":
    main()
