"""第四阶段设计用数值参考：生成系数、频响和期望向量，不执行 RTL 或硬件测试。"""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
FS_HZ = 250
TAPS = 63
FC_HZ = 40
COEFF_FRAC = 16
DC_FRAC = 16
DC_SHIFT = 5


def coefficients():
    index = np.arange(TAPS, dtype=float) - (TAPS - 1) / 2
    ideal = 2 * FC_HZ / FS_HZ * np.sinc(2 * FC_HZ / FS_HZ * index) * np.hamming(TAPS)
    ideal /= ideal.sum()
    quantized = np.rint(ideal * (1 << COEFF_FRAC)).astype(np.int64)
    # 只修正中心系数，保证对称和精确单位直流增益。
    quantized[TAPS // 2] += (1 << COEFF_FRAC) - int(quantized.sum())
    return ideal, [int(value) for value in quantized]


def round_away(value, fraction):
    magnitude = (abs(int(value)) + (1 << (fraction - 1))) >> fraction
    return -magnitude if value < 0 else magnitude


def saturate(value, width):
    low, high = -(1 << (width - 1)), (1 << (width - 1)) - 1
    return max(low, min(high, int(value)))


def dc_fixed(samples):
    baseline = None
    output = []
    for sample in samples:
        sample = int(sample)
        assert -32768 <= sample <= 32767
        if baseline is None:
            baseline = sample << DC_FRAC
            output.append(0)
            continue
        error = (sample << DC_FRAC) - baseline
        output.append(round_away(error, DC_FRAC))
        baseline += error >> DC_SHIFT
        assert -(1 << 31) <= baseline < (1 << 31)
        assert -65535 <= output[-1] <= 65535
    return output


def fir_fixed(samples, coeff, out_width=18):
    # 使用无界整数点积作参考；没有复刻未来 RTL 的串行 MAC 状态机。
    output = []
    maximum = 0
    for n in range(len(samples)):
        acc = sum(int(samples[n-k]) * coeff[k] for k in range(min(n+1, len(coeff))))
        maximum = max(maximum, abs(acc))
        output.append(saturate(round_away(acc, COEFF_FRAC), out_width))
    return output, maximum


def dc_float(samples):
    baseline = None
    values = []
    for sample in samples:
        if baseline is None:
            baseline = float(sample)
            values.append(0.0)
        else:
            error = float(sample) - baseline
            values.append(error)
            baseline += error / (1 << DC_SHIFT)
    return np.asarray(values)


def response(freq, coeff):
    omega = 2 * np.pi * np.asarray(freq) / FS_HZ
    fir = np.exp(-1j * np.outer(omega, np.arange(len(coeff)))) @ (np.asarray(coeff) / (1 << COEFF_FRAC))
    alpha = 1 / (1 << DC_SHIFT)
    dc = (1 - np.exp(-1j*omega)) / (1 - (1-alpha) * np.exp(-1j*omega))
    return fir, dc * fir


def db(value):
    return 20 * np.log10(np.maximum(np.abs(value), 1e-15))


def generate(output_dir):
    output_dir.mkdir(parents=True, exist_ok=True)
    coeff_dir = ROOT / "data/reference/stage4"
    coeff_dir.mkdir(parents=True, exist_ok=True)
    ideal, coeff = coefficients()
    assert coeff == coeff[::-1] and sum(coeff) == 65536
    assert all(-(1 << 17) <= c < (1 << 17) for c in coeff)
    memory = "".join(f"{c & ((1 << 18)-1):05X}\n" for c in coeff)
    # 固定LF字节，避免Windows文本换行转换导致系数文件哈希不一致。
    (coeff_dir / "fir_lp_63_q16.mem").write_bytes(memory.encode("ascii"))
    with (coeff_dir / "fir_lp_63_q16.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(["tap", "coefficient_integer", "fraction_bits", "coefficient_float"])
        writer.writerows((i, c, COEFF_FRAC, c / 65536) for i, c in enumerate(coeff))

    frequencies = np.linspace(0, FS_HZ / 2, 25001)
    fir_h, total_h = response(frequencies, coeff)
    fir_db, total_db = db(fir_h), db(total_h)
    passband = (frequencies >= 5) & (frequencies <= 30)
    stopband = frequencies >= 50
    assert float(total_db[passband].min()) >= -0.25
    assert float(total_db[passband].max()) <= 0.25
    assert float(total_db[stopband].max()) <= -55
    with (output_dir / "frequency_response.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(["frequency_hz", "fir_gain_db", "dc_and_fir_gain_db"])
        writer.writerows((float(f), float(a), float(b)) for f, a, b in zip(frequencies[::50], fir_db[::50], total_db[::50]))

    rng = np.random.default_rng(20261030)
    cases = {
        "constant_zero": [0] * 512,
        "constant_bias": [21953] * 512,
        "constant_max": [32767] * 512,
        "constant_min": [-32768] * 512,
        "impulse": [0] * 128 + [20000] + [0] * 511,
        "positive_step": [0] * 128 + [32767] * 512,
        "negative_step": [0] * 128 + [-32768] * 512,
        "sign_reversal": [32767] * 128 + [-32768] * 512,
        "fullscale_alternating": [-32768, 32767] * 512,
        "random_fullscale": rng.integers(-32768, 32768, size=4096).tolist(),
    }
    tone_results = []
    for frequency in [5, 10, 20, 30, 50, 60, 80, 100]:
        t = np.arange(4000) / FS_HZ
        cases[f"tone_{frequency}hz"] = np.rint(6000 + 10000 * np.sin(2*np.pi*frequency*t)).astype(int).tolist()
    results = []
    for name, samples in cases.items():
        dc = dc_fixed(samples)
        filtered, max_acc = fir_fixed(dc, coeff)
        # 独立 NumPy 卷积核查无界点积，防止参考的抽头方向/索引写错。
        convolution = np.convolve(np.asarray(dc, dtype=np.int64), np.asarray(coeff, dtype=np.int64))[:len(dc)]
        direct = [saturate(round_away(int(x), COEFF_FRAC), 18) for x in convolution]
        assert direct == filtered
        float_reference = np.convolve(dc_float(samples), np.asarray(coeff)/65536)[:len(samples)]
        error = float(np.max(np.abs(np.asarray(filtered) - float_reference)))
        assert error <= 2.0
        assert max_acc < (1 << 40)
        assert all(-(1 << 17) <= x < (1 << 17) for x in filtered)
        if name.startswith("constant"):
            assert not any(dc) and not any(filtered)
        if name in ("positive_step", "negative_step", "sign_reversal"):
            assert max(abs(x) for x in filtered[-64:]) <= 1
        with (output_dir / f"{name}.csv").open("w", newline="", encoding="utf-8") as file:
            writer = csv.writer(file)
            writer.writerow(["sample_index", "input_s16", "dc_s17", "fir_s18"])
            writer.writerows(zip(range(len(samples)), samples, dc, filtered))
        result = dict(case=name, samples=len(samples), max_float_quantized_coeff_error_counts=error, maximum_abs_accumulator=max_acc)
        results.append(result)
        if name.startswith("tone_"):
            frequency = int(name.split("_")[1][:-2])
            time = np.arange(2000, 4000) / FS_HZ
            basis = np.exp(-2j*np.pi*frequency*time)
            source = np.asarray(samples[2000:])
            destination = np.asarray(filtered[2000:])
            amplitude_in = abs(2*np.dot(source, basis)/len(time))
            amplitude_out = abs(2*np.dot(destination, basis)/len(time))
            gain_db = float(db(amplitude_out/amplitude_in))
            if 5 <= frequency <= 30:
                assert -0.25 <= gain_db <= 0.25
            else:
                assert gain_db <= -50
            tone_results.append(dict(frequency_hz=frequency, measured_integer_model_gain_db=gain_db))

    # 系数符号对齐的极值激励核对累加界限；窄输出参数覆盖舍入后的饱和方向。
    worst = [65535 if c >= 0 else -65535 for c in coeff[::-1]]
    _, peak = fir_fixed(worst, coeff)
    bound = 65535 * sum(abs(c) for c in coeff)
    assert peak == bound
    assert round_away(32768, 16) == 1 and round_away(-32768, 16) == -1
    assert round_away(32767, 16) == 0 and round_away(-32767, 16) == 0
    assert fir_fixed([65535] * 128, coeff, out_width=8)[0][-1] == 127
    assert fir_fixed([-65535] * 128, coeff, out_width=8)[0][-1] == -128

    summary = dict(status="PASS_NUMERIC_DESIGN_ONLY", sample_rate_hz=FS_HZ, taps=TAPS,
                   window="Hamming", lowpass_design_frequency_hz=FC_HZ, dc_shift=DC_SHIFT,
                   dc_fraction_bits=DC_FRAC, coefficient_fraction_bits=COEFF_FRAC,
                   coefficient_sum=sum(coeff), coefficient_abs_sum=sum(abs(c) for c in coeff),
                   coefficient_memory_sha256=hashlib.sha256(memory.encode("ascii")).hexdigest(),
                   fir_group_delay_samples=31, fir_group_delay_ms=124,
                   combined_passband_min_db=float(total_db[passband].min()),
                   combined_passband_max_db=float(total_db[passband].max()),
                   combined_stopband_worst_db=float(total_db[stopband].max()),
                   accumulator_abs_bound=bound, fir_output_abs_bound_counts=bound/65536,
                   worst_case_coefficient_quantization_l1_error=float(np.sum(np.abs(ideal-np.asarray(coeff)/65536))),
                   cases=results, tones=tone_results,
                   limitations=["未编写或仿真新RTL", "未综合实现或测资源", "采样率是标称假设，实物抖动与漏样待查",
                                "去直流不能替代传感器校准", "5Hz是通带验收下限，不是严格高通截止频率"])
    (output_dir / "design_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({k: summary[k] for k in ["status", "combined_passband_min_db", "combined_passband_max_db",
                     "combined_stopband_worst_db", "accumulator_abs_bound", "fir_output_abs_bound_counts", "tones"]}, ensure_ascii=False, indent=2))
    print(f"PASS numerical cases={len(results)}; RTL_NOT_RUN; output={output_dir}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="第四阶段数值设计与期望向量生成")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/stage4_reference")
    generate(parser.parse_args().output_dir)
