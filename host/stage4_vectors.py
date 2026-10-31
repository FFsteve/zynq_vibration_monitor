"""从独立数值参考生成仿真输入；不读取DUT输出生成期望。"""
import argparse
import csv
import json
from pathlib import Path
import numpy as np
from stage4_reference import ROOT, coefficients, dc_fixed, fir_fixed


def generate(destination):
    reference=ROOT/'build/stage4_reference'
    summary=json.loads((reference/'design_summary.json').read_text(encoding='utf-8'))
    destination.mkdir(parents=True,exist_ok=True)
    total=0
    with (destination/'vectors.txt').open('w',encoding='ascii',newline='\n') as out:
        for case in summary['cases']:
            with (reference/(case['case']+'.csv')).open(newline='',encoding='utf-8') as source:
                for index,row in enumerate(csv.DictReader(source)):
                    out.write(f"{int(index==0)} {row['input_s16']} {row['dc_s17']} {row['fir_s18']}\n")
                    total+=1
    n=np.arange(4000)
    inputs=np.column_stack([np.rint(6000+10000*np.sin(2*np.pi*10*n/250)),
                            np.rint(-7000+9000*np.sin(2*np.pi*30*n/250)),
                            np.rint(21900+6000*np.sin(2*np.pi*60*n/250))]).astype(int)
    coeff=coefficients()[1]
    outputs=np.column_stack([fir_fixed(dc_fixed(inputs[:,axis]),coeff)[0] for axis in range(3)])
    with (destination/'triple_vectors.txt').open('w',encoding='ascii',newline='\n') as out:
        for sample,(raw,result) in enumerate(zip(inputs,outputs)):
            out.write(' '.join(str(int(v)) for v in [*raw,*result])+'\n')
    # 集成仿真覆盖两个以上的序号回绕；不是物理采样日志。
    with (destination/'link_vectors.txt').open('w',encoding='ascii',newline='\n') as out:
        for raw,result in zip(inputs[:600],outputs[:600]):
            out.write(' '.join(str(int(v)) for v in [*raw,*result])+'\n')
    manifest={'scalar_samples':total,'triple_samples':4000,'link_samples':600,'cases':summary['cases']}
    (destination/'vectors_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'PASS stage4 vectors scalar={total} triple=4000 link=600')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description='第四阶段仿真向量生成')
    parser.add_argument('--output-dir',type=Path,default=ROOT/'build/stage4_vectors')
    generate(parser.parse_args().output_dir)
