"""对实际RTL导出逐项评分；缺失、截短或多余结果均失败。"""
import argparse
import json
from pathlib import Path
from stage5_reference import ROOT


def rows(path):
    return [[int(v) for v in line.split()] for line in path.read_text(encoding='ascii').splitlines() if line.strip()]


def check(engine):
    base=ROOT/'build'/f'{engine}_stage5'
    vectors=ROOT/'build/stage5_vectors'
    window=rows(base/'window_features/window_capture.txt')
    link=rows(base/'feature_monitor_core/feature_link_capture.txt')
    alarm=rows(base/'threshold_alarm/alarm_capture.txt')
    assert window==rows(vectors/'window_expected.txt'),'窗口导出与独立期望不同'
    assert link==rows(vectors/'feature_link_expected.txt'),'全链路导出与独立期望不同'
    assert alarm==[r[-4:] for r in rows(vectors/'alarm_vectors.txt')],'报警导出与独立期望不同'
    for result in window+link:
        for mean,rms,peak in zip(result[3:6],result[6:9],result[9:12]):
            assert rms*rms<=mean<(rms+1)**2 and rms<=peak<=131072
    summary=dict(status='PASS_STAGE5_RTL_CAPTURES',simulator=engine,window_results=len(window),
                 link_results=len(link),alarm_cycles=len(alarm),alarm_axes=[r[12] for r in link])
    (base/'capture_summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    print('PASS stage5 captures '+json.dumps(summary))


if __name__=='__main__':
    p=argparse.ArgumentParser(description='核查第五阶段实际RTL导出')
    p.add_argument('--simulator',choices=['modelsim','xsim'],required=True)
    check(p.parse_args().simulator)
