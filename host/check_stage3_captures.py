"""将 ModelSim/XSim 的真实串行输出捕获交给 PC 日志链路验收。"""
from datetime import datetime
from pathlib import Path
import sys
from capture import main


def run():
    root=Path(__file__).resolve().parents[1]
    output=root/"build"/"pc_stage3"/datetime.now().strftime("run_%Y%m%d_%H%M%S_%f")
    for engine in ("modelsim", "xsim"):
        base=root/"build"/f"{engine}_stage3"/"top"
        for mode in ("frame", "ack"):
            result=main(["--input-bin",str(base/f"top_{mode}_capture.bin"),"--mode",mode,
                         "--expected-csv",str(base/f"top_{mode}_expected.csv"),"--expect-count","24",
                         "--output",str(output/f"{engine}_{mode}")])
            if result:
                return result
    for mode in ("frame", "ack"):
        a=(root/"build/modelsim_stage3/top"/f"top_{mode}_capture.bin").read_bytes()
        b=(root/"build/xsim_stage3/top"/f"top_{mode}_capture.bin").read_bytes()
        if a!=b:
            print("FAIL: 两仿真器捕获不一致")
            return 1
    print(f"PASS stage3_captures output={output}")
    return 0


if __name__=="__main__":
    sys.exit(run())
