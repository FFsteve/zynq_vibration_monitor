"""核对静止/运动记录与原始ILA，按数值匹配定位窗口，不假定计数器已清零。"""

import bisect
import csv
import hashlib
import json
import math
import statistics
import zipfile

import numpy as np
import analyze_session_20261101 as parser
from analyze_filter_test_2_20261101 import calibrated, stats, wire_bounds
from host.stage4_reference import dc_fixed, fir_fixed, round_away, saturate
from host.stage5_reference import feature_block, AlarmReference

ROOT=parser.ROOT
BASE=ROOT/'report/evidence/fixed_filter_ila_20261101/filter_test_4'
OUT=ROOT/'report/evidence/filter_test_4_20261101_analysis'
NAMES={'static':['static_uart_d0.csv','static_uart_d1.csv','static_i2c.csv'],
       'motion':['uart_d0_motion.csv','uart_d1_motion.csv','i2c_motion.csv']}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(row):
    value={key:row[key] for key in ['Sample in Buffer','TRIGGER','debug_feature_valid_o','debug_quality_valid_o',
                                  'debug_alarm_valid_o','debug_alarm_axes_o[2:0]','debug_window_id_o[31:0]',
                                  'debug_seq_start_o[7:0]','debug_seq_end_o[7:0]','debug_rx_frame_count_o[31:0]',
                                  'debug_completed_count_o[31:0]','debug_filter_restart_count_o[31:0]',
                                  'debug_aborted_windows_o[31:0]','debug_dropped_count_o[31:0]']}
    for name in ['ms','rms','peak']:
        value[name]=[row[f'debug_{name}_{axis}_o[{34 if name=="ms" else 17}:0]'] for axis in 'xyz']
    return value


def analyze(label,params,coeff):
    folder=BASE/label;parser.BASE=folder
    hashes={p.name:sha(p) for p in folder.iterdir() if p.is_file()}
    with zipfile.ZipFile(folder/f'{label}.atkdl') as z:
        assert z.testzip() is None
        conf=dict(line.split('=',1) for line in z.read('set.ini').decode('utf-8-sig').splitlines() if '=' in line)
        settings=json.loads(conf['settingData'])
    with zipfile.ZipFile(folder/'ila.ila') as z:
        assert z.testzip() is None
        assert z.read('waveform.csv')==(folder/'ila.csv').read_bytes()
        embedded_csv_sha=hashlib.sha256(z.read('waveform.csv')).hexdigest()
        ila_members=[i.filename for i in z.infolist()]
    with (folder/'ila.csv').open(encoding='utf-8-sig',newline='') as f:
        reader=csv.reader(f);header=next(reader);radix=next(reader)
        rows=[{key:int(value,10 if index<3 else 16) for index,(key,value) in enumerate(zip(header,line))} for line in reader]
    assert len(rows)==1024 and len(header)==24 and all('HEX'==radix[i] for i in range(3,24))
    assert [r['Sample in Buffer'] for r in rows]==list(range(1024))
    events=[snapshot(row) for row in rows if row['debug_feature_valid_o']]
    assert len(events)==1 and events[0]['Sample in Buffer']==512
    assert [r['Sample in Buffer'] for r in rows if r['TRIGGER']]==[512]
    before,after=snapshot(rows[0]),snapshot(rows[512])
    for s in [before,after]:
        assert s['rms']==[math.isqrt(v) for v in s['ms']]
        assert all(peak*peak>=ms for peak,ms in zip(s['peak'],s['ms']))
        assert (s['debug_seq_end_o[7:0]']-s['debug_seq_start_o[7:0]'])%256==127
    # 快照在非feature事件时可以保留旧窗口；仅事件发布的数据用于当前窗口精确匹配。
    n0,n1,ni=NAMES[label]
    d0=parser.uart(n0);d1=parser.uart(n1);bus=parser.i2c(ni)
    assert not bus['problems'] and not bus['partial_packets']
    assert all(not d1[k] for k in ['warnings','byte_issues','bad_checksums','gaps','skipped'])
    assert not parser.summary(d1['frames'])['sequence_errors']
    bursts=[t for t in bus['transactions'] if t['register']=='3B' and t['mode']=='read']
    replies=d1['frames'];inputs=d0['frames']
    assert len(bursts)==len(replies) and inputs[0]['seq']==replies[0]['seq']==0
    reads={t['register']:t['data'] for t in bus['transactions'] if t['mode']=='read' and t['register'] in ['75','6B','1A','19','1C','38']}
    assert reads=={'75':'68','6B':'01','1A':'02','19':'03','1C':'00','38':'01'}
    reply_times=[r['time'] for r in replies];source=[];input_map={};calibration_bad=[];delays=[]
    for f in inputs:
        n=bisect.bisect_left(reply_times,f['time'])
        assert n<len(replies) and replies[n]['seq']==f['seq'] and 0<reply_times[n]-f['time']<.002
        assert n not in input_map;input_map[n]=f
        delays.append((reply_times[n]-f['time'])*1e6)
    for n,(burst,reply) in enumerate(zip(bursts,replies)):
        assert 0<reply['time']-burst['end']<.002
        axes=calibrated(burst['data'],params)
        if n in input_map and axes!=input_map[n]['axes']:calibration_bad.append(n)
        source.append({'seq':reply['seq'],'time':reply['time'],'axes':axes,
                       'source':'measured_d0' if n in input_map else 'i2c_calibration_reconstruction'})
    assert inputs[0]['time']>.012
    internal=[]
    for a in range(3):
        dc=dc_fixed([f['axes'][a] for f in source]);axis,_=fir_fixed(dc,coeff)
        conv=np.convolve(np.asarray(dc,dtype=np.int64),np.asarray(coeff,dtype=np.int64))[:len(dc)]
        assert axis==[saturate(round_away(int(v),16),18) for v in conv]
        internal.append(axis)
    filter_bad=[]
    for n,reply in enumerate(replies):
        expected=[internal[a][n]>>2 for a in range(3)]
        if expected!=reply['axes']:filter_bad.append({'index':n,'expected':expected,'observed':reply['axes']})
    # 对运动缺测之后的纯实测连续段另作未知基线范围核查，隔离重建假设。
    runs=[]
    for n in sorted(input_map):
        if not runs or n!=runs[-1][-1]+1:runs.append([])
        runs[-1].append(n)
    independent=[]
    for run in runs:
        if len(run)<=1024:continue
        bounds=[wire_bounds([input_map[n]['axes'][a] for n in run],coeff) for a in range(3)]
        unique=0;bad=[]
        for j in range(1024,len(run)):
            unique+=int(all(lo[j]==hi[j] for lo,hi in bounds))
            if any(not lo[j]<=replies[run[j]]['axes'][a]<=hi[j] for a,(lo,hi) in enumerate(bounds)):bad.append(run[j])
        independent.append({'first_input_s':input_map[run[0]]['time'],'checked_frames':len(run)-1024,
                            'exact_unique_frames':unique,'mismatch_indices':bad})
    windows=[];alarm=AlarmReference()
    for begin in range(62,len(source)-127,128):
        feature=feature_block([[internal[a][j] for a in range(3)] for j in range(begin,begin+128)])
        state=alarm.feed(feature['mean_square'])
        windows.append({'local_window':len(windows),'begin_index':begin,'end_index':begin+127,
                        'first_seq':source[begin]['seq'],'last_seq':source[begin+127]['seq'],
                        'first_input_s':input_map[begin]['time'] if begin in input_map else None,
                        'last_input_s':input_map[begin+127]['time'] if begin+127 in input_map else None,
                        'ms':feature['mean_square'],'rms':feature['rms'],'peak':feature['peak'],
                        'predicted_alarm_mask':sum(int(v)<<a for a,v in enumerate(state['axes'])),
                        'rises':state['rises'],'falls':state['falls'],
                        'reconstructed_inputs':sum(j not in input_map for j in range(begin,begin+128))})
    comparisons=[]
    for name,s in [('before',before),('feature_event',after)]:
        matches=[w for w in windows if w['first_seq']==s['debug_seq_start_o[7:0]'] and w['last_seq']==s['debug_seq_end_o[7:0]']
                 and all(w[key]==s[key] for key in ['ms','rms','peak'])]
        # 若ID非零，搜索数值匹配以定位窗口；不拿累计ID强行当本次采集下标。
        candidates=[]
        for w in matches:
            n=w['end_index']
            # 非事件拍保存的是旧窗口，接收计数已继续推进，不能用旧窗末项倒推计数基值。
            rxbase=s['debug_rx_frame_count_o[31:0]']-(n+1) if name=='feature_event' else None
            candidates.append({'local_window':w['local_window'],'window_id_offset':s['debug_window_id_o[31:0]']-w['local_window'],
                               'rx_count_before_this_record':rxbase,'window':w,
                               'alarm_matches_model':w['predicted_alarm_mask']==s['debug_alarm_axes_o[2:0]']})
        comparisons.append({'position':name,'ila':s,'exact_matches':candidates})
    # 保留未匹配时最接近候选，供诊断文件时段而非修改参考使其通过。
    nearest=[]
    for s in [before,after]:
        candidates=[w for w in windows if w['first_seq']==s['debug_seq_start_o[7:0]'] and w['last_seq']==s['debug_seq_end_o[7:0]']]
        nearest.append(sorted([{'local_window':w['local_window'],'ms':w['ms'],'rms':w['rms'],'peak':w['peak'],
                                'distance':sum(abs(x-y) for x,y in zip(w['ms'],s['ms']))} for w in candidates],key=lambda w:w['distance'])[:2])
    with (OUT/f'{label}_frames.csv').open('w',encoding='utf-8',newline='') as f:
        writer=csv.writer(f);writer.writerow(['index','reply_time_s','seq','input_source','input_x','input_y','input_z',
                                             'reference_fir_x','reference_fir_y','reference_fir_z','wire_x','wire_y','wire_z'])
        for n,(src,reply) in enumerate(zip(source,replies)):
            writer.writerow([n,reply['time'],src['seq'],src['source'],*src['axes'],*[internal[a][n] for a in range(3)],*reply['axes']])
    result={'original_sha256':hashes,'archive_crc_ok':True,'ila_archive_crc_ok':True,'ila_csv_equals_embedded':True,
            'ila_members':ila_members,'ila_embedded_csv_sha256':embedded_csv_sha,'settings':settings,
            'startup_readbacks':reads,'i2c_transactions':len(bus['transactions']),'axis_reads':len(bursts),
            'i2c_trailing_boundary':bus['trailing_detail'],'measured_calibration_frames':len(input_map),'calibration_mismatches':calibration_bad,
            'd0':{k:v for k,v in d0.items() if k not in ['frames','groups']},'d1':{k:v for k,v in d1.items() if k not in ['frames','groups']},
            'd0_summary':parser.summary(inputs),'d1_summary':parser.summary(replies),
            'reconstructed_d0':[{'index':n,'seq':s['seq'],'reply_time_s':s['time']} for n,s in enumerate(source) if n not in input_map],
            'filter_checked_frames':len(replies),'filter_mismatches':filter_bad,'measured_only_independent_reference':independent,
            'ila_sample_count':len(rows),'ila_feature_event_count':len(events),'ila_trigger_index':512,
            'ila_feature_pulse_cycles':sum(r['debug_feature_valid_o'] for r in rows),'ila_quality_values':sorted(set(r['debug_quality_valid_o'] for r in rows)),
            'ila_feature_field_change_indices':{key:[i for i in range(1,len(rows)) if rows[i][key]!=rows[i-1][key]]
                                                for key in header[7:19]},
            'ila_alarm_valid_transitions':[(r['Sample in Buffer'],r['debug_alarm_valid_o']) for i,r in enumerate(rows) if i==0 or r['debug_alarm_valid_o']!=rows[i-1]['debug_alarm_valid_o']],
            'ila_comparisons':comparisons,'nearest_windows_if_unmatched':nearest,'reference_windows':windows,
            'ila_event_exact_window_match':len(comparisons[1]['exact_matches'])==1,
            'ila_screenshots_reviewed':True,
            'reply_delay_us':{'mean':statistics.mean(delays),'min':min(delays),'max':max(delays)},
            'input_stats':stats(inputs),'restored_output_stats':stats(replies,4),
            'max_reference_rms':[max(w['rms'][a] for w in windows) for a in range(3)]}
    assert not calibration_bad and not filter_bad
    assert all(sha(folder/name)==value for name,value in hashes.items())
    (OUT/f'{label}_analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return result


def main():
    OUT.mkdir(exist_ok=True)
    params_path=ROOT/'report/mpu6050_calibration_params_20261101.json'
    params=json.loads(params_path.read_text(encoding='utf-8'))
    mem=ROOT/'data/reference/stage4/fir_lp_63_q16.mem'
    manifest=json.loads((ROOT/'build/release/v1.0-rc1/source_manifest.json').read_text(encoding='utf-8'))
    assert sha(mem)==manifest['files'][str(mem.relative_to(ROOT)).replace('\\','/')]
    coeff=[int(s,16) for s in mem.read_text().splitlines() if s.strip()]
    coeff=[c-(1<<18) if c&(1<<17) else c for c in coeff]
    assert len(coeff)==63 and sum(coeff)==65536
    compact={}
    for label in NAMES:
        r=analyze(label,params,coeff)
        compact[label]={'measured_d0':r['d0']['oracle']['frames'],'d1':r['d1']['oracle']['frames'],
                        'calibration_matches':r['measured_calibration_frames'],'reconstructed_d0':r['reconstructed_d0'],
                        'filter_matches':r['filter_checked_frames'],'ila_comparisons':r['ila_comparisons'],
                        'ila_event_exact_window_match':r['ila_event_exact_window_match'],
                        'ila_alarm_valid_transitions':r['ila_alarm_valid_transitions'],
                        'max_reference_rms':r['max_reference_rms'],'independent':r['measured_only_independent_reference']}
    (OUT/'summary.json').write_text(json.dumps({'user_operation_note':'用户确认static未重新下载FPGA，motion重新下载；两次ILA均在对应DL16采集中触发；累计计数不默认从本次记录清零',
                                             'parameter_sha256':sha(params_path),'coefficient_sha256':sha(mem),
                                             'cases':compact},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(compact,ensure_ascii=False))
    print('PASS filter_test_4_analysis_completed originals_unchanged')


if __name__=='__main__':
    main()
