"""复核实际RTL导出，或按显式模式换算实物二进制记录；不猜数据来源。"""
import argparse,csv,json,math
from pathlib import Path
import numpy as np
from stage4_reference import ROOT
from protocol import StreamDecoder


def rows(path):
    return [[int(v) for v in line.split()] for line in path.read_text(encoding='ascii').splitlines() if line.strip()]


def decode_bytes(data):
    decoder=StreamDecoder();samples=decoder.feed(data)
    return samples,decoder.stats()


def amplitude(values,freq):
    n=np.arange(len(values));angle=2*np.pi*freq*n/250
    coefficients=np.linalg.lstsq(np.column_stack([np.sin(angle),np.cos(angle),np.ones(len(values))]),values,rcond=None)[0]
    return float(np.hypot(*coefficients[:2]))


def check(engine):
    folder=ROOT/'build'/f'{engine}_stage6/system_monitor_core';vectors=ROOT/'build/stage6_vectors'
    stimulus=rows(vectors/'system_vectors.txt');expected=np.array([r[5:8] for r in stimulus],dtype=np.int64)
    features=rows(vectors/'system_features.txt');summaries={};decoded_modes={};internal_modes={}
    for label,mode in [('raw',0),('filtered',1)]:
        data=(folder/f'wire_{label}.bin').read_bytes()
        assert data==(vectors/f'expected_{label}.bin').read_bytes(),f'{label}完整线缆字节不同'
        samples,stats=decode_bytes(data)
        decoded_modes[label]=samples
        assert len(samples)==5632 and stats['trailing_bytes']==0 and stats['checksum_errors']==0
        internal_modes[label]=rows(folder/f'internal_{label}.txt')
        assert internal_modes[label]==[[r[1],*r[5:8]] for r in stimulus],f'{label}内部滤波不同'
        assert rows(folder/f'features_{label}.txt')==features,f'{label}窗口/报警不同'
        latency=rows(folder/f'latency_{label}.txt')
        assert latency==[[i,198 if mode else 4] for i in range(5632)],f'{label}处理延迟不同'
        wire_timing=rows(folder/f'wire_timing_{label}.txt')
        assert len(wire_timing)==56320 and [r[0] for r in wire_timing]==list(range(56320))
        for i in range(5632):
            starts=[r[1] for r in wire_timing[i*10:i*10+10]]
            assert starts==[starts[0]+j*100 for j in range(10)],'包内字节间隔不是完整10位时间'
        summaries[label]=dict(wire_bytes=len(data),frames=len(samples),features=len(features),tx_start_latency_clks=latency[0][1],compressed_packet_wire_clks=1000)
        if mode:
            restored=np.array([[s.x*4,s.y*4,s.z*4] for s in samples],dtype=np.int64)
            observed=np.array([r[1:] for r in internal_modes[label]],dtype=np.int64)
            error=observed-restored
            assert int(error.min())>=0 and int(error.max())<=3
    for case in range(1,4):
        actual=observed[4096+(case-1)*512:4096+case*512]
        for axis in range(3):
            if axis!=case-1:assert np.count_nonzero(actual[:,axis])==0,'三轴串扰'
    gains=[]
    for axis,(freq,source_amplitude) in enumerate(zip([10,30,60],[10000,9000,6000])):
        full_amplitude=amplitude(observed[1000:4000,axis],freq)
        wire_amplitude=amplitude(restored[1000:4000,axis],freq)
        gain=20*math.log10(full_amplitude/source_amplitude)
        wire_gain=20*math.log10(wire_amplitude/source_amplitude)
        if freq<50:assert -.5<gain<.5 and -.5<wire_gain<.5
        else:assert gain<-50 and wire_gain<-50
        gains.append(dict(axis='XYZ'[axis],frequency_hz=freq,gain_db=gain,wire_restored_gain_db=wire_gain))
    with (folder/'samples_comparison.csv').open('w',encoding='utf-8',newline='') as f:
        writer=csv.writer(f)
        writer.writerow(['sample_index','synthetic_case','seq','raw_x','raw_y','raw_z','filtered_x_s18','filtered_y_s18','filtered_z_s18','wire_x_s16','wire_y_s16','wire_z_s16','restored_x','restored_y','restored_z'])
        for i,(raw,wire) in enumerate(zip(decoded_modes['raw'],decoded_modes['filtered'])):
            writer.writerow([i,stimulus[i][0],raw.seq,raw.x,raw.y,raw.z,*observed[i],wire.x,wire.y,wire.z,*restored[i]])
    with (folder.parent/'quantification.csv').open('w',encoding='utf-8',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=['axis','frequency_hz','gain_db','wire_restored_gain_db']);writer.writeheader();writer.writerows(gains)
    result=dict(status='PASS_STAGE6_RTL_CAPTURES',simulator=engine,source='SYNTHETIC_RTL',modes=summaries,
                selector_scale=4,restore_error_min=int(error.min()),restore_error_max=int(error.max()),
                gain_results=gains,axis_isolation='PASS',sample_rate_hz=250,compressed_sample_clks=4608,
                limitations=['非实测','频率时间采用均匀250Hz假设','包内没有模式标识，外部必须记录模式'])
    for label in ['raw','filtered','ack']:
        timing=rows(folder.parent/'system_top'/f'top_timing_{label}.txt')
        length=1 if label=='ack' else 10
        assert len(timing)==4*length
        packet_starts=[timing[i*length][1] for i in range(4)]
        assert [packet_starts[i+1]-packet_starts[i] for i in range(3)]==[200000,200000,400000]
        for i in range(4):
            starts=[r[1] for r in timing[i*length:(i+1)*length]]
            assert starts==[starts[0]+j*4340 for j in range(length)]
    result['default_packet_wire_clks']=43400
    result['default_packet_wire_us']=868
    result['default_sample_clks']=200000
    (folder.parent/'capture_summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS stage6 actual RTL captures '+json.dumps(result,ensure_ascii=False))


def recording(path,mode,output):
    samples,stats=decode_bytes(path.read_bytes());scale=4 if mode=='filtered' else 1
    output.mkdir(parents=True,exist_ok=True)
    target=output/'samples_scaled.csv';metadata=output/'recording_summary.json'
    if target.exists() or metadata.exists():raise FileExistsError('输出已有记录，拒绝覆盖证据')
    with target.open('x',encoding='utf-8',newline='') as f:
        writer=csv.writer(f);writer.writerow(['sample_index','seq','x_counts','y_counts','z_counts'])
        writer.writerows((i,s.seq,s.x*scale,s.y*scale,s.z*scale) for i,s in enumerate(samples))
    result=dict(source_file=str(path.resolve()),source_mode=mode,restore_scale=scale,decoder=stats,
                physical_test_pass=None,limitations=['仅换算与解码，不自动认定实测通过','不从文件数据推断真实采样率','不将截断记录或缺包补零','模式由操作者提供，无法从包内验证'])
    metadata.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    group=p.add_mutually_exclusive_group(required=True)
    group.add_argument('--simulator',choices=['modelsim','xsim']);group.add_argument('--input-bin',type=Path)
    p.add_argument('--source-mode',choices=['raw','filtered']);p.add_argument('--output',type=Path)
    args=p.parse_args()
    if args.simulator:check(args.simulator)
    else:
        if not args.source_mode or args.output is None:p.error('实物或离线记录必须显式提供--source-mode及新--output目录')
        recording(args.input_bin,args.source_mode,args.output)
