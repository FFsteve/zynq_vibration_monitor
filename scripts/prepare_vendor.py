"""从用户合法持有的本地库导入锁定依赖，核验全部文件后才复制，不下载或重新授权。"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    source = args.source.resolve()
    root = args.root.resolve()
    manifest = json.loads((root / "stm32/vendor_manifest.json").read_text(encoding="utf-8"))
    for name, expected in manifest["files"].items():
        path = source / name
        if not path.is_file() or digest(path) != expected:
            raise ValueError("库版本/内容不符：" + name)
    destination = root / "stm32/Libraries"
    for name, expected in manifest["files"].items():
        path = destination / name
        if path.exists() and digest(path) != expected:
            raise FileExistsError("目标已有不同版本，不覆盖：" + str(path))
    for name in manifest["files"]:
        src, dest = source / name, destination / name
        if src.resolve() == dest.resolve():
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        assert digest(dest) == manifest["files"][name]
    print("PASS_VENDOR_IMPORT files=" + str(len(manifest["files"])))


if __name__ == "__main__":
    main()

