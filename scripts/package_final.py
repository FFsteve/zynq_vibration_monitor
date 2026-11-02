"""按公开源码清单生成独立本地工程包，另保存原许可第三方依赖，不覆盖已有内容。"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# 仅这两份报告按用户明确要求保留中文名称，其余自有路径继续检查ASCII及空白。
REPORT_FILES = {"word": "report/技术文档word版.docx", "pdf": "report/技术文档pdf版.pdf"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "zynq_vibration_monitor_final")
    args = parser.parse_args()
    output = args.output.resolve()
    if output == ROOT or output.is_relative_to(ROOT / ".git"):
        raise ValueError("输出目录不安全")
    if output.exists() and any(output.iterdir()):
        raise FileExistsError("输出目录不为空；请选择新的目录，禁止覆盖冻结包")
    # 清单同时包括已提交文件与尚未提交但未被忽略的自有文件；排除本地包递归收录。
    raw = subprocess.check_output(["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=ROOT)
    files = set(item.decode("utf-8") for item in raw.split(b"\0") if item)
    # bit、ltx、hex为全局忽略扩展，但board是本次明确选择的发布成果。
    files.update(p.relative_to(ROOT).as_posix() for p in (ROOT / "board").rglob("*") if p.is_file())
    files.update(name for name in REPORT_FILES.values() if (ROOT / name).is_file())
    report_complete = all((ROOT / name).is_file() for name in REPORT_FILES.values())
    allowed_dirs = {"rtl", "constr", "sim", "host", "scripts", "stm32", "data", "docs", "report", "skill", "board"}
    allowed_roots = {"README.md", "AGENTS.md", "LICENSE", "THIRD_PARTY_NOTICES.md", ".gitignore", ".gitattributes"}
    selected = []
    for name in sorted(files):
        path = ROOT / name
        if not path.is_file() or path.is_relative_to(output):
            continue
        if name not in allowed_roots and name.split("/")[0] not in allowed_dirs:
            continue
        if "__pycache__" in path.parts or name.startswith("stm32/Libraries/"):
            continue
        # 原英文名初稿继续留在工作区，不再与用户补图后的正式版本重复收录。
        if report_complete and name == "report/design_report.docx":
            continue
        if (not name.isascii() and name not in REPORT_FILES.values()) or any(c.isspace() for c in name):
            raise ValueError("路径不是无空格ASCII：" + name)
        selected.append(name)
    output.mkdir(parents=True, exist_ok=True)
    for name in selected:
        src, dst = ROOT / name, output / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        assert digest(src) == digest(dst), name
    # 第三方目录只复制到用户请求的本地工程包，保留原版权、许可、目录，不提交到Git。
    vendor = json.loads((ROOT / "stm32/vendor_manifest.json").read_text(encoding="utf-8"))
    for name, expected in vendor["files"].items():
        src, dst = ROOT / "stm32/Libraries" / name, output / "stm32/Libraries" / name
        assert digest(src) == expected
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        assert digest(dst) == expected
    manifest = dict(version="v1.0-buzzer-20261102", vivado_version="2020.2",
                    source_commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip(),
                    design_report_complete=report_complete,
                    design_report_files=REPORT_FILES,
                    design_report_status="设计报告及照片已归档" if report_complete else "设计报告未齐备",
                    third_party="本地依赖保留原许可，非MIT自有代码，公开Git不收录",
                    exclusions=["原Vivado工程与缓存", "工具安装包和厂商PDF", "全部长期原始采样"],
                    files={p.relative_to(output).as_posix():digest(p) for p in sorted(output.rglob("*")) if p.is_file()})
    (output / "package_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(status="PASS_PACKAGE_COPY", files=len(manifest["files"]),
                         bytes=sum(p.stat().st_size for p in output.rglob("*") if p.is_file()),
                         output=str(output)), ensure_ascii=False))


if __name__ == "__main__":
    main()

