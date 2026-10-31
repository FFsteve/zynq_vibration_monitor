"""生成第五阶段独立期望；使用Python整数、math.isqrt及已验证滤波参考。"""
import json
import math
import random
from pathlib import Path
import numpy as np
from stage5_reference import ROOT, feature_block, AlarmReference
from stage4_reference import coefficients, dc_fixed, fir_fixed


def write_rows(path,rows):
    path.write_text(''.join(' '.join(str(int(x)) for x in row)+'\n' for row in rows),encoding='ascii')


def generate():
    out=ROOT/'build/stage5_vectors'
    out.mkdir(parents=True,exist_ok=True)
    summary=json.loads((ROOT/'build/stage5_reference/design_summary.json').read_text(encoding='utf-8'))
    rng=random.Random(51031)
    samples=[]
    expected=[]
    # 定向窗口后追加100个全量程随机窗口；单独核查首末冲击。
    blocks=[[(0,0,0)]*128,[(2000,-1500,32767)]*128,[(-131072,)*3]*128,[(131071,)*3]*128,
            [(-131072,131071,-1),(131071,-131072,1)]*64,
            [(-131072,5000,-9000)]+[(0,0,0)]*127,[(0,0,0)]*127+[(-131072,5000,-9000)],
            [(round(10000*math.sin(2*math.pi*10*i/128)),round(8000*math.cos(2*math.pi*13*i/128)),round(5000*math.sin(2*math.pi*17*i/128))) for i in range(128)]]
    blocks += [[tuple(rng.randrange(-131072,131072) for _ in range(3)) for i in range(128)] for _ in range(101)]
    for i,block in enumerate(blocks):
        samples.extend(block)
        e=feature_block(block)
        expected.append([i,(250+128*i)%256,(250+128*i+127)%256,*e['mean_square'],*e['rms'],*e['peak']])
    write_rows(out/'window_samples.txt',samples)
    write_rows(out/'window_expected.txt',expected)
    alarm=AlarmReference()
    traces=[]
    directed=[(0,0,0),(4000000,0,0),(4000000,0,0),(3062500,0,0),(2250000,0,0),
              (3062500,0,0),(2250000,0,0),(2250000,0,0)]
    directed += [tuple(rng.choice([0,2249999,2250000,2250001,3999999,4000000,4000001,1<<34]) for _ in range(3)) for _ in range(5000)]
    for i,values in enumerate(directed):
        clear=(i%113==112)
        valid=(i%17!=16)
        if clear:alarm.clear();rises=falls=0
        elif valid:
            result=alarm.feed(values)
            rises=sum(1<<a for a in result['rises']);falls=sum(1<<a for a in result['falls'])
        else:rises=falls=0
        axes=sum(int(v)<<a for a,v in enumerate(alarm.axes))
        traces.append([int(clear),int(valid),*values,axes,int(alarm.valid),rises,falls])
    write_rows(out/'alarm_vectors.txt',traces)
    # 低振幅、持续高振幅、恢复低振幅三段；均为合成输入，不是板测。
    rows=[]
    for i in range(1600):
        amplitude=(6000,1000,9000) if 256<=i<1024 else (0,0,0)
        rows.append(tuple(round(offset+amplitude[a]*math.sin(2*math.pi*f*i/250))
                          for a,(offset,f) in enumerate(zip([6000,-7000,21900],[10,20,30]))))
    coeff=coefficients()[1]
    filtered=np.column_stack([fir_fixed(dc_fixed(np.array(rows)[:,a]),coeff)[0] for a in range(3)]).tolist()
    write_rows(out/'feature_link_samples.txt',[list(raw)+list(fil) for raw,fil in zip(rows,filtered)])
    features=[];alarm=AlarmReference()
    for start in range(62,len(rows)-127,128):
        e=feature_block(filtered[start:start+128]);result=alarm.feed(e['mean_square'])
        features.append([len(features),(251+start)%256,(251+start+127)%256,*e['mean_square'],*e['rms'],*e['peak'],
                         sum(int(v)<<a for a,v in enumerate(result['axes'])),
                         sum(1<<a for a in result['rises']),sum(1<<a for a in result['falls'])])
    assert len(features)==12 and any(x[-3] for x in features) and features[-1][-3]==0
    write_rows(out/'feature_link_expected.txt',features)
    manifest=dict(window_samples=len(samples),window_results=len(expected),alarm_cycles=len(traces),link_samples=len(rows),link_results=len(features),sqrt_vectors=summary['sqrt_vectors'])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('PASS stage5 vectors '+json.dumps(manifest))


if __name__=='__main__':generate()
