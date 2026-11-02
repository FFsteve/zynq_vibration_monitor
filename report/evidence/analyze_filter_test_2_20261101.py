"""核查校准固件与真实滤波，区分D0缺测及未知初始滤波状态。"""

import bisect
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics
import zipfile

import analyze_session_20261101 as parser

ROOT = parser.ROOT
BASE = ROOT/'report/evidence/fixed_filter_ila_20261101/filter_test_2'
OUT = ROOT/'report/evidence/filter_test_2_20261101_analysis'


def rounded(value, bits):
    q=(abs(value)+(1<<(bits-1)))>>bits
    return q if value>=0 else -q


def clipped(value,width):
    return max(-(1<<(width-1)),min((1<<(width-1))-1,value))


def calibrated(data, params):
    raw=[int.from_bytes(bytes.fromhex(data)[i:i+2],'big',signed=True) for i in [0,2,4]]
    return [clipped(rounded((v*65536-params['bias_q16'][i])*params['gain_q16'][i],32),16) for i,v in enumerate(raw)]


def dc_sequence(values, baseline):
    output=[]
    for v in values:
        error=(v<<16)-baseline
        output.append(rounded(error,16))
        baseline+=error>>5
    return output


def fir(values,coeff):
    return [clipped(rounded(sum(values[n-k]*coeff[k] for k in range(min(n+1,63))),16),18)
            for n in range(len(values))]


def wire_bounds(values, coeff):
    # 基线范围按signed32全范围作保守传播；前62样本FIR历史未知，不用于判定。
    lower_dc=dc_sequence(values,(1<<31)-1)
    upper_dc=dc_sequence(values,-(1<<31))
    lo=[];hi=[]
    for n in range(len(values)):
        acc_lo=acc_hi=0
        for k in range(min(n+1,63)):
            c=coeff[k];a,b=lower_dc[n-k],upper_dc[n-k]
            acc_lo+=c*(a if c>=0 else b);acc_hi+=c*(b if c>=0 else a)
        lo.append(clipped(rounded(acc_lo,16),18)>>2)
        hi.append(clipped(rounded(acc_hi,16),18)>>2)
    return lo,hi


def stats(frames,scale=1):
    return {'samples':len(frames),'mean':[statistics.mean(f['axes'][i]*scale for f in frames) for i in range(3)],
            'std':[statistics.stdev(f['axes'][i]*scale for f in frames) for i in range(3)],
            'min':[min(f['axes'][i]*scale for f in frames) for i in range(3)],
            'max':[max(f['axes'][i]*scale for f in frames) for i in range(3)]}


def main():
    OUT.mkdir(exist_ok=True);parser.BASE=BASE
    hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in BASE.iterdir() if p.is_file()}
    with zipfile.ZipFile(BASE/'filter_test_2.atkdl') as z:
        assert z.testzip() is None
        config=dict(line.split('=',1) for line in z.read('set.ini').decode('utf-8-sig').splitlines() if '=' in line)
        settings=json.loads(config['settingData'])
    d0=parser.uart('filter_test_2_uart_d0.csv');d1=parser.uart('filter_test_2_uart_d1.csv')
    bus=parser.i2c('filter_test_2_i2c.csv')
    assert not bus['problems']
    params_path=ROOT/'report/mpu6050_calibration_params_20261101.json'
    params=json.loads(params_path.read_text(encoding='utf-8'))
    bursts=[t for t in bus['transactions'] if t['register']=='3B' and t['mode']=='read']
    burst_ends=[t['end'] for t in bursts]
    reply_times=[f['time'] for f in d1['frames']]
    measured_map={};calibration_mismatches=[];calibration_checks=0;input_to_reply=[];i2c_to_input=[]
    for f in d0['frames']:
        j=bisect.bisect_left(reply_times,f['time'])
        candidates=[k for k in range(j,min(j+2,len(reply_times))) if 0<reply_times[k]-f['time']<0.002 and d1['frames'][k]['seq']==f['seq']]
        assert len(candidates)==1
        assert candidates[0] not in measured_map
        measured_map[candidates[0]]=f
        input_to_reply.append((reply_times[candidates[0]]-f['time'])*1e6)
        i=bisect.bisect_right(burst_ends,f['time'])-1
        if i>=0 and f['time']-bursts[i]['end']<0.001:
            expected=calibrated(bursts[i]['data'],params);calibration_checks+=1
            if expected!=f['axes']:calibration_mismatches.append({'frame':f,'expected':expected})
            i2c_to_input.append((f['time']-bursts[i]['end'])*1e6)
        else:
            assert f==d0['frames'][0]
    # D1序号连续、I2C连续；D0缺测处仅用已核对的校准公式重建输入，明确标注来源。
    source=[];missing=[];matched_bursts=set()
    for index,reply in enumerate(d1['frames']):
        i=bisect.bisect_right(burst_ends,reply['time'])-1
        if i>=0 and reply['time']-bursts[i]['end']<0.002:
            assert i not in matched_bursts;matched_bursts.add(i)
            value=calibrated(bursts[i]['data'],params)
            if index in measured_map:assert measured_map[index]['axes']==value
        else:
            assert index==0 and index in measured_map
            value=measured_map[index]['axes']
        origin='measured_d0' if index in measured_map else 'i2c_calibration_reconstruction'
        if origin!='measured_d0':missing.append({'reply_time_s':reply['time'],'seq':reply['seq']})
        source.append({'seq':reply['seq'],'axes':value,'time':reply['time'],'source':origin})
    assert not calibration_mismatches and len(matched_bursts)==len(bursts)
    assert not d1['bad_checksums'] and not d1['warnings'] and not d1['byte_issues']
    assert len(d1['groups'])==1 and not parser.summary(d1['frames'])['sequence_errors']
    mem=ROOT/'data/reference/stage4/fir_lp_63_q16.mem'
    manifest=json.loads((ROOT/'build/release/v1.0-rc1/source_manifest.json').read_text(encoding='utf-8'))
    assert hashlib.sha256(mem.read_bytes()).hexdigest()==manifest['files'][str(mem.relative_to(ROOT)).replace('\\','/')]
    coeff=[int(line.strip(),16) for line in mem.read_text().splitlines() if line.strip()]
    coeff=[v-(1<<18) if v&(1<<17) else v for v in coeff]
    assert len(coeff)==63 and sum(coeff)==65536
    expected=[];low=[];high=[]
    for axis in range(3):
        values=[f['axes'][axis] for f in source]
        # 点参考假定首样本建立基线，仅用于展示；实际初始状态未知。
        point_dc=[0]+dc_sequence(values[1:],values[0]<<16)
        expected.append([v>>2 for v in fir(point_dc,coeff)])
        lo,hi=wire_bounds(values,coeff)
        low.append(lo);high.append(hi)
    warmup=1024;exact_frames=0;range_mismatches=[];point_max=[0,0,0];interval_width_max=[0,0,0]
    for n in range(warmup,len(source)):
        unique=True
        for a in range(3):
            observed=d1['frames'][n]['axes'][a]
            point_max[a]=max(point_max[a],abs(observed-expected[a][n]))
            interval_width_max[a]=max(interval_width_max[a],high[a][n]-low[a][n])
            if not low[a][n]<=observed<=high[a][n]:range_mismatches.append({'sample':n,'axis':a,'observed':observed,'range':[low[a][n],high[a][n]]})
            unique&=low[a][n]==high[a][n]
        exact_frames+=int(unique)
    # 每个实测连续段重新给定完全未知的基线范围；该核查不使用任何I2C重建输入。
    measured_runs=[]
    for n in sorted(measured_map):
        if not measured_runs or n!=measured_runs[-1][-1]+1:
            measured_runs.append([])
        measured_runs[-1].append(n)
    independent_segments=[]
    for run in measured_runs:
        if len(run)<=warmup:continue
        bounds=[wire_bounds([measured_map[n]['axes'][a] for n in run],coeff) for a in range(3)]
        mismatches=[];unique_frames=0
        for j in range(warmup,len(run)):
            unique=True
            for a,(lo,hi) in enumerate(bounds):
                observed=d1['frames'][run[j]]['axes'][a]
                if not lo[j]<=observed<=hi[j]:mismatches.append({'sample':run[j],'axis':a})
                unique&=lo[j]==hi[j]
            unique_frames+=int(unique)
        independent_segments.append({'measured_frames':len(run),'input_start_s':measured_map[run[0]]['time'],
                                     'first_checked_reply_time_s':reply_times[run[warmup]],
                                     'last_reply_time_s':reply_times[run[-1]],'checked_frames':len(run)-warmup,
                                     'unique_exact_frames':unique_frames,'mismatches':mismatches})
    with (OUT/'comparison.csv').open('w',encoding='utf-8',newline='') as stream:
        writer=csv.writer(stream);writer.writerow(['index','reply_time_s','seq','input_source','input_x','input_y','input_z','wire_x','wire_y','wire_z','restored_x','restored_y','restored_z','point_x','point_y','point_z','low_x','low_y','low_z','high_x','high_y','high_z'])
        for n,(src,reply) in enumerate(zip(source,d1['frames'])):
            writer.writerow([n,reply['time'],reply['seq'],src['source'],*src['axes'],*reply['axes'],*[v*4 for v in reply['axes']],*[expected[a][n] for a in range(3)],*[low[a][n] for a in range(3)],*[high[a][n] for a in range(3)]])
    result={'scope':'STM32校准后真实输入与FPGA滤波回传；用户确认未重配FPGA、STM32启动后才采集，约5.76秒开始移动且可能碰探头',
            'original_sha256':hashes,'archive_crc_ok':True,'settings':settings,
            'calibration_id':params['calibration_id'],'parameter_sha256':hashlib.sha256(params_path.read_bytes()).hexdigest(),
            'coefficient_sha256':hashlib.sha256(mem.read_bytes()).hexdigest(),
            'd0':{k:v for k,v in d0.items() if k not in ['frames','groups']},
            'd1':{k:v for k,v in d1.items() if k not in ['frames','groups']},
            'd0_segments':[parser.summary(g) for g in d0['groups']],'d1_summary':parser.summary(d1['frames']),
            'i2c_transactions':len(bus['transactions']),'i2c_register_counts':dict(parser.Counter(t['register'] for t in bus['transactions'])),
            'i2c_problems':bus['problems'],'calibration_measured_matches':calibration_checks,'calibration_mismatches':calibration_mismatches,
            'measured_d0_frames':len(d0['frames']),'d1_frames':len(d1['frames']),'reconstructed_missing_d0':missing,
            'input_to_reply_us':{'mean':statistics.mean(input_to_reply),'min':min(input_to_reply),'max':max(input_to_reply)},
            'i2c_to_calibrated_d0_us':{'mean':statistics.mean(i2c_to_input),'min':min(i2c_to_input),'max':max(i2c_to_input)},
            'reference':{'initial_state_known':False,'input_stream_uses_i2c_reconstruction':True,'warmup_samples':warmup,
                         'checked_frames':len(source)-warmup,'first_checked_reply_time_s':source[warmup]['time'],
                         'exact_unique_range_frames':exact_frames,'range_width_max_wire_counts':interval_width_max,
                         'point_reference_max_wire_difference':point_max,'range_mismatches':range_mismatches,
                         'note':'连续D1和I2C支持参考连续推进；假定系数与rc1一致、期间无隐蔽历史重启，重建输入不冒充实测D0，首段不作完整已知初态验收'},
            'measured_only_reference':{'uses_reconstructed_inputs':False,'warmup_samples_per_segment':warmup,
                                       'segments':independent_segments,
                                       'checked_frames':sum(s['checked_frames'] for s in independent_segments),
                                       'unique_exact_frames':sum(s['unique_exact_frames'] for s in independent_segments)},
            'before_motion':{'d0':stats([f for f in d0['frames'] if f['time']<5.5]),'d1_restored':stats([f for f in d1['frames'] if f['time']<5.5],4)},
            'after_6p1s':{'d0':stats([f for f in d0['frames'] if f['time']>=6.1]),'d1_restored':stats([f for f in d1['frames'] if f['time']>=6.1],4)},
            'whole_capture_clean_uart_pass':False,'whole_capture_known_initial_state_exact_pass':False}
    (OUT/'analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    assert all(hashlib.sha256((BASE/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
    print(json.dumps({'measured_d0':len(d0['frames']),'d1':len(d1['frames']),'i2c':len(bursts),'calibration_matches':calibration_checks,
                      'missing_d0':len(missing),'reference':result['reference'],'measured_only_reference':result['measured_only_reference'],
                      'before_motion':result['before_motion'],
                      'input_to_reply_us':result['input_to_reply_us'],'i2c_to_d0_us':result['i2c_to_calibrated_d0_us']},ensure_ascii=False))
    print('PASS filter_test_2_analysis_completed originals_unchanged')


if __name__=='__main__':
    main()
