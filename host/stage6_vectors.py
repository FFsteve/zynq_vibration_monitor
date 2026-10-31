"""生成完整链路长序列和三轴隔离期望，独立于RTL状态机。"""
import json,math
from pathlib import Path
from stage4_reference import ROOT,coefficients,dc_fixed,fir_fixed
from stage5_reference import feature_block,AlarmReference
from protocol import Sample,encode


def generate():
    out=ROOT/'build/stage6_vectors';out.mkdir(parents=True,exist_ok=True)
    coeff=coefficients()[1];all_rows=[];features=[];raw_bytes=bytearray();filtered_bytes=bytearray()
    for case,n in enumerate([4096,512,512,512]):
        rows=[]
        for i in range(n):
            values=[6000,-7000,21900]
            for a,(amplitude,freq) in enumerate(zip([10000,9000,6000],[10,30,60])):
                if case==0 or case==a+1:values[a]+=round(amplitude*math.sin(2*math.pi*freq*i/250))
            rows.append(values)
        filtered=list(zip(*[fir_fixed(dc_fixed([r[a] for r in rows]),coeff)[0] for a in range(3)]))
        base=251 if case==0 else 77
        for i,(raw,fil) in enumerate(zip(rows,filtered)):
            seq=(base+i)%256
            all_rows.append([case,seq,*raw,*fil])
            raw_bytes+=encode(Sample(seq,*raw));filtered_bytes+=encode(Sample(seq,*(x//4 for x in fil)))
        alarm=AlarmReference()
        for start in range(62,n-127,128):
            e=feature_block(filtered[start:start+128]);r=alarm.feed(e['mean_square'])
            features.append([len(features),(base+start)%256,(base+start+127)%256,*e['mean_square'],*e['rms'],*e['peak'],sum(int(v)<<a for a,v in enumerate(r['axes']))])
    for name,rows in [('system_vectors.txt',all_rows),('system_features.txt',features)]:
        (out/name).write_text(''.join(' '.join(str(v) for v in row)+'\n' for row in rows),encoding='ascii')
    (out/'expected_raw.bin').write_bytes(raw_bytes);(out/'expected_filtered.bin').write_bytes(filtered_bytes)
    manifest=dict(samples=len(all_rows),features=len(features),cases=[4096,512,512,512],source='SYNTHETIC',fs_hz=250,filtered_shift=2,
                  analysis_start=1000,analysis_count=3000,frequencies_hz=[10,30,60],input_amplitudes=[10000,9000,6000])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    assert len(all_rows)==5632 and len(features)==40
    print('PASS stage6 vectors samples=5632 features=40 cases=4')


if __name__=='__main__':generate()
