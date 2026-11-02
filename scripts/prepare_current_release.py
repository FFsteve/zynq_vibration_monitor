"""把已验证蜂鸣器下载成果和精简实测证据归档到当前公开交付目录，不重新构建或烧录。"""
import gzip
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and digest(destination) != digest(source):
        raise FileExistsError("目标已有不同内容，不覆盖：" + str(destination))
    shutil.copy2(source, destination)


def main():
    board = ROOT / "board"
    original = ROOT / "build/buzzer_release/debug"
    build = json.loads((ROOT / "report/evidence/buzzer_20261101/build.json").read_text(encoding="utf-8"))
    software = json.loads((ROOT / "report/evidence/buzzer_20261101/software_checks.json").read_text(encoding="utf-8"))
    for name, expected in software["source_sha256"].items():
        assert digest(ROOT / name) == expected, "当前源码与构建证据不一致：" + name
    names = ["system.bit", "system.ltx", "utilization.rpt", "timing_summary.rpt", "internal_setup.rpt",
             "internal_hold.rpt", "drc.rpt", "cdc.rpt", "io.rpt", "probe_map.tsv", "release_result.txt"]
    for name in names:
        assert digest(original / name) == build["artifact_sha256"][name], name
        copy(original / name, board / "fpga/debug" / name)
    firmware = ROOT / "build/stm32_calibration_versions/sixface_r1_20261101_validated/vibration_monitor.hex"
    assert digest(firmware) == "895bbfa1f1076716d045b9235c65d62adbddf2c927687b5f0cc3e177c75a41d5"
    copy(firmware, board / "stm32/vibration_monitor.hex")
    copy(ROOT / "build/stm32/SensorCalibratedTrial/keil_build.log", board / "stm32/keil_build.txt")
    for name in ["STM32F10x_StdPeriph_Driver/LICENSE.txt", "CMSIS/CM3/DeviceSupport/ST/STM32F10x/LICENSE.txt"]:
        copy(ROOT / "stm32/Libraries" / name, board / "third_party" / name)
    # 原头部的ARM版权/免责条款属于随固件分发的说明，不改写其原文。
    core = ROOT / "stm32/Libraries/CMSIS/CM3/CoreSupport/core_cm3.c"
    notice = core.read_text(encoding="utf-8").split('#include')[0]
    path = board / "third_party/arm_notice.txt"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(notice, encoding="utf-8")
    copy(ROOT / "build/buzzer_sim_run.log", board / "validation/buzzer_sim.txt")
    copy(ROOT / "build/buzzer_build_run.log", board / "validation/buzzer_build.txt")
    for path in (ROOT / "build/stage7_regression").glob("*"):
        if path.suffix in {".log", ".json"}:
            copy(path, board / "validation/stage7" / (path.stem + (".txt" if path.suffix == ".log" else ".json")))
    copy(ROOT / "report/evidence/buzzer_20261101/build.json", board / "validation/build_at_generation.json")
    copy(ROOT / "report/evidence/buzzer_20261101/software_checks.json", board / "validation/buzzer_software.json")
    write_json(board / "board_confirmation.json", dict(
        date="2026-11-02", version="v1.0-buzzer-20261102",
        result="USER_CONFIRMED_PHYSICAL_BUZZER_PASS",
        source="当前聊天用户明确报告：已最后一次上板已经测试完。蜂鸣器可以正常响应。",
        performed_by="用户", assistant_operated_board=False, new_audio_or_waveform_attached=False))
    vendor = ROOT / "stm32/Libraries"
    write_json(ROOT / "stm32/vendor_manifest.json", dict(
        status="EXTERNAL_DEPENDENCY_LOCK", public_mit_source=False,
        versions={"spl":"V3.6.2", "cmsis_device":"V3.5.1", "core_support":"V1.30"},
        files={path.relative_to(vendor).as_posix():digest(path) for path in sorted(vendor.rglob("*")) if path.is_file()}))
    measured = ROOT / "data/measured/filter_test_3"
    measured.mkdir(parents=True, exist_ok=True)
    compressed, uncompressed = {}, {}
    for label in ["d0", "d1"]:
        source = ROOT / ("report/evidence/fixed_filter_ila_20261101/filter_test_3/filter_test_3_uart_" + label + ".csv")
        name = "uart_" + label + ".csv"
        target = measured / (name + ".gz")
        target.write_bytes(gzip.compress(source.read_bytes(), mtime=0))
        assert gzip.decompress(target.read_bytes()) == source.read_bytes()
        compressed[target.name] = digest(target)
        uncompressed[name] = digest(source)
    write_json(measured / "source_identity.json", dict(
        files=compressed, uncompressed_files=uncompressed, encoding="gb18030",
        original_directory="report/evidence/fixed_filter_ila_20261101/filter_test_3",
        transformation="gzip无损压缩，解压字节与原导出完全相同"))
    for label in ["static", "motion"]:
        source = ROOT / "report/evidence/fixed_filter_ila_20261101/filter_test_4" / label / "ila.csv"
        copy(source, ROOT / "data/measured/ila" / (label + ".csv"))
    payload = {p.relative_to(ROOT).as_posix():digest(p) for p in sorted(board.rglob("*"))
               if p.is_file() and p.name != "artifacts.json"}
    write_json(board / "artifacts.json", dict(version="v1.0-buzzer-20261102", vivado="2020.2",
                                            files=payload))
    print("PASS_PREPARE_RELEASE artifacts=" + str(len(payload)))


if __name__ == "__main__":
    main()

