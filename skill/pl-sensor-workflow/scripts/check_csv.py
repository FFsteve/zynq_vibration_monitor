"""按可配置列映射对照独立参考和实测整数，缺列、空数据和不匹配均拒绝。"""
import argparse
import csv
import io
import json


def check(stream, profile):
    pairs = profile["pairs"]
    if not pairs or any(len(pair) != 2 for pair in pairs):
        raise ValueError("列映射必须包含参考列和实测列")
    reader = csv.DictReader(stream)
    required = {name for pair in pairs for name in pair}
    selector = profile.get("include_column")
    if selector:
        required.add(selector)
    if not required.issubset(set(reader.fieldnames or [])):
        raise ValueError("CSV缺少所需列")
    rows = skipped = 0
    for row in reader:
        if selector and row[selector] != str(profile.get("include_value", "1")):
            skipped += 1
            continue
        rows += 1
        for expected, measured in pairs:
            if int(row[expected]) != int(row[measured]):
                raise ValueError(f"第{rows}行不一致：{expected}/{measured}")
    if rows < max(1, int(profile.get("minimum_rows", 1))):
        raise ValueError("有效记录为空或不足")
    return dict(status="PASS_CSV_COMPARISON", rows=rows, skipped_rows=skipped, columns=len(pairs))


def self_test():
    profile = {"pairs": [["golden_temperature", "device_temperature"]], "minimum_rows": 2}
    good = "golden_temperature,device_temperature\n-20,-20\n125,125\n"
    assert check(io.StringIO(good), profile)["rows"] == 2
    rejected = 0
    for bad in [good.replace("125,125", "125,124"), "", "x,y\n1,1\n", "golden_temperature,device_temperature\n"]:
        try:
            check(io.StringIO(bad), profile)
        except (ValueError, KeyError, TypeError):
            rejected += 1
        else:
            raise RuntimeError("错误或空输入未被拒绝")
    assert rejected == 4
    assert check(io.StringIO(good), profile)["rows"] == 2
    return dict(status="PASS_SELF_TEST", valid_cases=2, rejected_cases=rejected,
                recovery=True, different_project_columns=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv")
    parser.add_argument("--profile")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = self_test()
    else:
        if not args.csv or not args.profile:
            parser.error("需要--csv和--profile")
        with open(args.profile, encoding="utf-8-sig") as stream:
            profile = json.load(stream)
        with open(args.csv, encoding="utf-8-sig", newline="") as stream:
            result = check(stream, profile)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()

