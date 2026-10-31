"""核查六份 ATK UART 记录，生成可追溯的实验校准参数和离线校正结果。"""
import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import re
import statistics
import zipfile

from protocol import StreamDecoder, decode

SOURCES = {
    "xp": ("xp_r1_uart.csv", "xp_r1.atkdl"),
    "xn": ("xn_r1_uart.csv", "xn_r1.atkdl"),
    "yp": ("yp_r1_uart.csv", "yp_r1.atkdl"),
    "yn": ("yn_r1_uart.csv", "yn_r1.atkdl"),
    "zp": ("sensor_source_d0_20261030.csv", "sensor_source_20261030.atkdl"),
    "zn": ("sensor_zdown_d0_20261030.csv", "sensor_zdown_20261030.atkdl"),
}


def rounded(value):
    return math.floor(value + 0.5) if value >= 0 else -math.floor(-value + 0.5)


def fixed_correct(raw, bias_q16, gain_q16):
    result, mask = [], 0
    for i, value in enumerate(raw):
        product = (value * 65536 - bias_q16[i]) * gain_q16[i]
        magnitude = (abs(product) + (1 << 31)) // (1 << 32)
        value = magnitude if product >= 0 else -magnitude
        if value < -32768 or value > 32767:
            mask |= 1 << i
        result.append(max(-32768, min(32767, value)))
    return result, mask


def seconds(value):
    number, unit = value.split()
    return float(number) * {"s": 1, "ms": 1e-3, "us": 1e-6, "μs": 1e-6,
                           "µs": 1e-6, "ns": 1e-9}[unit]


def archive_info(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError(f"波形归档 CRC 错误：{path}")
        text = archive.read("set.ini").decode("utf-8-sig")
        settings = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
        config = json.loads(settings["settingData"])
        decoders = []
        for entry in json.loads(settings["decodeJson"]):
            uart = entry.get("decodeJson", {}).get("UART")
            if uart:
                decoders.append({"channels": {p["id"]: p["value"] for p in uart["opt_channels"]},
                                 "options": {p["id"]: p["value"] for p in uart["options"]}})
        return {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "crc_ok": True,
                "settings": config, "uart_decoders": decoders}


def read_capture(csv_path, archive_path):
    raw = csv_path.read_bytes()
    try:
        text, encoding = raw.decode("utf-8-sig"), "utf-8-sig"
    except UnicodeDecodeError:
        text, encoding = raw.decode("gb18030"), "gb18030"
    rows = list(csv.reader(io.StringIO(text)))[1:]
    records = [{"index": int(r[0]), "time": seconds(r[1]), "duration": seconds(r[2]),
                "kind": r[3], "value": r[4]} for r in rows if len(r) >= 5]
    words = [r for r in records if r["kind"] == "TX data" and re.fullmatch(r"[0-9A-Fa-f]{2}", r["value"])]
    starts = [r for r in records if r["kind"] == "TX data" and r["value"] == "Start bit"]
    stops = [r for r in records if r["kind"] == "TX data" and r["value"] == "Stop bit"]
    frames, skipped, errors = [], [], []
    offset = 0
    while offset < len(words):
        block = words[offset:offset + 10]
        if len(block) == 10 and [r["value"].upper() for r in block[:2]] == ["A5", "5A"]:
            try:
                sample = decode(bytes(int(r["value"], 16) for r in block))
            except ValueError as error:
                errors.append({"word_offset": offset, "error": str(error)})
            else:
                bounds = []
                for word in block:
                    begin = [r for r in starts if 0 < word["time"] - r["time"] < 15e-6]
                    end = [r for r in stops if abs(r["time"] - word["time"] - word["duration"]) < 0.2e-6]
                    if len(begin) != 1 or len(end) != 1:
                        raise ValueError(f"完整包存在缺失起止位：{csv_path}，索引{word['index']}")
                    bits = [r for r in records if r["kind"] == "TX bits" and
                            begin[0]["time"] < r["time"] < end[0]["time"]]
                    if len(bits) != 8 or any(r["value"] not in ("0", "1") for r in bits):
                        raise ValueError(f"数据位记录不完整：{csv_path}")
                    if sum(int(r["value"]) << i for i, r in enumerate(bits)) != int(word["value"], 16):
                        raise ValueError(f"位记录与字节解码不一致：{csv_path}")
                    bounds.append((begin[0]["time"], end[0]["time"] + end[0]["duration"]))
                frames.append({"seq": sample.seq, "raw": [sample.x, sample.y, sample.z],
                               "start_s": bounds[0][0], "end_s": bounds[-1][1]})
                offset += 10
                continue
        skipped.append({"word_offset": offset, **words[offset]})
        offset += 1
    if not frames:
        raise ValueError(f"无完整合法包：{csv_path}")
    decoder = StreamDecoder()
    crosscheck = decoder.feed(bytes(int(r["value"], 16) for r in words))
    if [(s.seq, [s.x, s.y, s.z]) for s in crosscheck] != [(f["seq"], f["raw"]) for f in frames]:
        raise ValueError("独立流式解码结果不一致")
    warnings = [r for r in records if r["kind"] not in ("TX data", "TX bits")]
    interior_warnings = [r for r in warnings if frames[0]["start_s"] <= r["time"] <= frames[-1]["end_s"]]
    intervals = [b["start_s"] - a["start_s"] for a, b in zip(frames, frames[1:])]
    interval_outliers = [{"from_seq": a["seq"], "to_seq": b["seq"], "seconds": b["start_s"] - a["start_s"]}
                         for a, b in zip(frames, frames[1:]) if not 0.0039 <= b["start_s"] - a["start_s"] <= 0.0041]
    axes = list(zip(*(f["raw"] for f in frames)))
    half = len(frames) // 2
    archive = archive_info(archive_path)
    return {"csv": str(csv_path), "csv_sha256": hashlib.sha256(raw).hexdigest(), "encoding": encoding,
            "archive": str(archive_path), "archive_info": archive, "frames": frames, "count": len(frames),
            "capture_seconds": archive["settings"]["setTime"] / 1000,
            "mean": [statistics.mean(a) for a in axes], "std": [statistics.stdev(a) for a in axes],
            "min": [min(a) for a in axes], "max": [max(a) for a in axes],
            "second_minus_first_half": [statistics.mean(a[half:]) - statistics.mean(a[:half]) for a in axes],
            "interval_mean_s": statistics.mean(intervals), "interval_min_s": min(intervals), "interval_max_s": max(intervals),
            "interval_outliers": interval_outliers,
            "decoder_stats": decoder.stats(), "candidate_checksum_errors": errors, "skipped_words": skipped,
            "warnings": warnings, "interior_warnings": interior_warnings}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("report/evidence"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError("输出目录已存在，请另选目录以保留旧分析")
    captures = {p: read_capture(args.input / c, args.input / a) for p, (c, a) in SOURCES.items()}
    bias = [(captures[a + "p"]["mean"][i] + captures[a + "n"]["mean"][i]) / 2 for i, a in enumerate("xyz")]
    sensitivity = [(captures[a + "p"]["mean"][i] - captures[a + "n"]["mean"][i]) / 2 for i, a in enumerate("xyz")]
    if any(s <= 0 for s in sensitivity):
        raise ValueError("灵敏度非正，请检查姿态名称、轴方向或解码")
    gain = [16384 / s for s in sensitivity]
    bias_q16, gain_q16 = [rounded(b * 65536) for b in bias], [rounded(k * 65536) for k in gain]
    issues = ["没有独立第二轮或跨重启验证记录", "新旧记录跨阶段，实际配置一致性尚未实测确认"]
    args.output.mkdir(parents=True)
    for pose, cap in captures.items():
        if cap["capture_seconds"] < 20 or cap["count"] < 4900:
            issues.append(f"{pose}仅{cap['capture_seconds']:g}秒/{cap['count']}包，未达到20秒采集计划")
        stats = cap["decoder_stats"]
        if stats["checksum_errors"] or stats["seq_discontinuities"] or cap["interior_warnings"]:
            issues.append(f"{pose}包含通信异常")
        if cap["interval_outliers"]:
            issues.append(f"{pose}存在超出3.9～4.1毫秒的包间隔，采样周期仍待核查")
        if any(v in (-32768, 32767) for f in cap["frames"] for v in f["raw"]):
            issues.append(f"{pose}出现原始数值到量程端点的情况，需要排查饱和")
        corrected = [[(v - bias[i]) / sensitivity[i] for i, v in enumerate(f["raw"])] for f in cap["frames"]]
        norm = [math.sqrt(sum(v * v for v in values)) for values in corrected]
        means = [statistics.mean(a) for a in zip(*corrected)]
        axis = "xyz".index(pose[0])
        cross = max(abs(means[i]) for i in range(3) if i != axis)
        if cross > 0.05:
            issues.append(f"{pose}横轴残差{cross:.6f}g超过建议0.05g，姿态/模型需核查")
        cap["fit_check"] = {"mean_g": means, "mean_norm_g": statistics.mean(norm), "max_cross_axis_g": cross,
                            "independent_validation": False}
        with (args.output / f"{pose}_corrected.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(["seq", "start_s", "raw_x", "raw_y", "raw_z", "x_g", "y_g", "z_g",
                             "corrected_x", "corrected_y", "corrected_z", "clipped_axes"])
            for frame, g in zip(cap["frames"], corrected):
                fixed, mask = fixed_correct(frame["raw"], bias_q16, gain_q16)
                writer.writerow([frame["seq"], frame["start_s"], *frame["raw"], *g, *fixed, mask])
    result = {"status": "EXPERIMENTAL_ONLY", "formal_calibration_pass": False,
              "bias_counts": bias, "sensitivity_counts_per_g": sensitivity, "gain": gain,
              "bias_q16": bias_q16, "gain_q16": gain_q16, "issues": issues, "captures": captures}
    identity = hashlib.sha256(json.dumps({p: c["csv_sha256"] for p, c in captures.items()}, sort_keys=True).encode()).hexdigest()
    result["source_set_sha256"] = identity
    (args.output / "analysis.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    header = "\n".join(["/* 由六面短记录生成的实验初值，尚未完成独立校准验收。 */",
                          f"/* 原始CSV集合SHA256：{identity} */", "#ifndef ACCEL_CALIBRATION_PARAMS_H",
                          "#define ACCEL_CALIBRATION_PARAMS_H", "#include <stdint.h>",
                          '#define ACCEL_CALIBRATION_ID "trial_20261031_short_capture"',
                          "static const int32_t accel_bias_q16[3]={" + ",".join(map(str, bias_q16)) + "};",
                          "static const int32_t accel_gain_q16[3]={" + ",".join(map(str, gain_q16)) + "};", "#endif", ""])
    (args.output / "accel_calibration_params.h").write_text(header, encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("status", "formal_calibration_pass", "bias_counts", "sensitivity_counts_per_g", "gain", "bias_q16", "gain_q16", "issues")}, ensure_ascii=False, indent=2))
    print("PASS calibration_analysis protocol_and_math_checked formal_calibration_pass=false")


if __name__ == "__main__":
    main()
