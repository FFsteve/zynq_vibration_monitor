"""检查交付文件身份、源代码/自检入口与可选第三方依赖，不以此替代仿真或板测。"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_files(root, files):
    for name, expected in files.items():
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or "\\" in name or ":" in name:
            raise ValueError("清单含越界路径")
        path = root.joinpath(*relative.parts).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError("文件缺失或越界：" + name)
        if digest(path) != expected:
            raise ValueError("文件身份不符：" + name)
    return len(files)


def verify(root, require_vendor=False):
    required = ["README.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "skill/README.md",
                "skill/pl-sensor-workflow/SKILL.md", "scripts/build_buzzer.ps1",
                "scripts/build_buzzer.tcl", "sim/run_buzzer.ps1",
                "stm32/keil/vibration_calibration.uvprojx",
                "report/mpu6050_calibration_params_20261101.json",
                "report/ai_records/old_thread.md", "report/ai_records/new_thread.md"]
    for name in required:
        if not (root / name).is_file():
            raise ValueError("缺少交付入口：" + name)
    rtl = list((root / "rtl").glob("*.v"))
    for source in rtl:
        if not (root / "sim/tb" / ("tb_" + source.name)).is_file():
            raise ValueError("缺少对应自检：" + source.name)
    if "2020.2" not in (root / "README.md").read_text(encoding="utf-8"):
        raise ValueError("未说明Vivado版本")
    board = json.loads((root / "board/artifacts.json").read_text(encoding="utf-8"))
    count = verify_files(root, board["files"])
    coefficient = root / "data/reference/stage4/fir_lp_63_q16.mem"
    if digest(coefficient) != "b9b74fb39759cf352d2b388ea15650b0a1522d1f15dd6f4861f622d7b580fc35":
        raise ValueError("系数身份不符")
    dependency = root / "stm32/Libraries"
    vendor_count = 0
    if require_vendor or dependency.exists():
        manifest = json.loads((root / "stm32/vendor_manifest.json").read_text(encoding="utf-8"))
        vendor_count = verify_files(dependency, manifest["files"])
    package_count = 0
    if (root / "package_manifest.json").exists():
        manifest = json.loads((root / "package_manifest.json").read_text(encoding="utf-8"))
        package_count = verify_files(root, manifest["files"])
        if manifest["design_report_complete"] is not False:
            raise ValueError("本次不应声称最终设计报告完成")
    return dict(status="PASS_DELIVERY_FILES", artifact_files=count, rtl_modules=len(rtl),
                package_files=package_count, vendor_files=vendor_count,
                vivado_version="2020.2", design_report_complete=False)


def self_test():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "sample.txt").write_text("证据", encoding="utf-8")
        files = {"sample.txt": digest(root / "sample.txt")}
        assert verify_files(root, files) == 1
        (root / "sample.txt").write_text("篡改", encoding="utf-8")
        failures = 0
        for bad in [files, {"../outside.txt": "0" * 64}]:
            try:
                verify_files(root, bad)
            except ValueError:
                failures += 1
            else:
                raise RuntimeError("反例未拒绝")
        (root / "sample.txt").write_text("证据", encoding="utf-8")
        assert verify_files(root, files) == 1
    return dict(status="PASS_VERIFIER_SELF_TEST", rejected_cases=failures, recovery=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--require-vendor", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    result = self_test() if args.self_test else verify(args.root.resolve(), args.require_vendor)
    print(json.dumps(result, ensure_ascii=False))

