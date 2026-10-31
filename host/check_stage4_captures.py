"""独立检查两套仿真器实际导出的样本，并测量RTL输出的基频增益。"""
import argparse
import csv
import json
from pathlib import Path
import numpy as np
from stage4_reference import ROOT


def check(engine):
    base=ROOT/f'build/{engine}_stage4'
    manifest=json.loads((ROOT/'build/stage4_vectors/vectors_manifest.json').read_text(encoding='utf-8'))
    with (ROOT/'build/stage4_vectors/vectors.txt').open() as source:
        vectors=[list(map(int,line.split())) for line in source]
    with (base/'fir_lp_serial/rtl_fir.csv').open() as source:
        fir=[int(row['output']) for row in csv.DictReader(source)]
    assert len(fir)==len(vectors)==41728
    assert fir==[r[3] for r in vectors]
    tones=[]
    offset=0
    for case in manifest['cases']:
        count=case['samples']
        if case['case'].startswith('tone_'):
            freq=int(case['case'].split('_')[1][:-2])
            raw=np.asarray([row[1] for row in vectors[offset+2000:offset+count]])
            actual=np.asarray(fir[offset+2000:offset+count])
            basis=np.exp(-2j*np.pi*freq*np.arange(2000,count)/250)
            gain=20*np.log10(max(abs(np.dot(actual,basis)/np.dot(raw,basis)),1e-15))
            assert (-0.25<=gain<=0.25) if freq<=30 else gain<=-50
            tones.append({'frequency_hz':freq,'rtl_gain_db':float(gain)})
        offset+=count
    with (ROOT/'build/stage4_vectors/triple_vectors.txt').open() as source:
        triple=np.asarray([list(map(int,line.split())) for line in source])
    with (base/'vibration_filter/rtl_triple.csv').open() as source:
        actual=np.asarray([[int(row[k]) for k in ['x','y','z']] for row in csv.DictReader(source)])
    assert actual.shape==(4000,3)
    assert np.array_equal(actual,triple[:,3:])
    axis_tones=[]
    for axis,freq in enumerate([10,30,60]):
        basis=np.exp(-2j*np.pi*freq*np.arange(2000,4000)/250)
        gain=20*np.log10(max(abs(np.dot(actual[2000:,axis],basis)/np.dot(triple[2000:,axis],basis)),1e-15))
        assert (-0.25<=gain<=0.25) if freq<=30 else gain<=-50
        axis_tones.append({'axis':axis,'frequency_hz':freq,'rtl_gain_db':float(gain)})
    result={'engine':engine,'status':'PASS_RTL_CAPTURE','fir_samples':len(fir),'triple_samples':len(actual),
            'fir_input_from_python_dc_reference':True,'triple_input_is_raw_s16':True,'scalar_tones':tones,'actual_three_axis_tones':axis_tones}
    (base/'capture_validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description='第四阶段RTL实际结果检查')
    parser.add_argument('--simulator',choices=['modelsim','xsim','both'],default='both')
    args=parser.parse_args()
    for engine in (['modelsim','xsim'] if args.simulator=='both' else [args.simulator]):
        check(engine)
