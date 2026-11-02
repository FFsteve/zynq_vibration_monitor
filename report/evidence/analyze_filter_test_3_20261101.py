"""核查第三次真实滤波记录及复位前ILA截图；不改变硬件和原始证据。"""

import csv
import hashlib
import json
import math
import statistics
import zipfile

import analyze_session_20261101 as parser
from analyze_filter_test_2_20261101 import calibrated, dc_sequence, fir, stats

ROOT = parser.ROOT
BASE = ROOT/'report/evidence/fixed_filter_ila_20261101/filter_test_3'
OUT = ROOT/'report/evidence/filter_test_3_20261101_analysis'


def fingerprint(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(exist_ok=True)
    parser.BASE = BASE
    hashes = {p.name:fingerprint(p) for p in BASE.iterdir() if p.is_file()}
    with zipfile.ZipFile(BASE/'filter_test_3.atkdl') as archive:
        assert archive.testzip() is None
        config = dict(line.split('=',1) for line in archive.read('set.ini').decode('utf-8-sig').splitlines() if '=' in line)
        settings = json.loads(config['settingData'])
    d0 = parser.uart('filter_test_3_uart_d0.csv')
    d1 = parser.uart('filter_test_3_uart_d1.csv')
    bus = parser.i2c('filter_test_3_i2c.csv')
    assert not bus['problems'] and not bus['partial_packets'] and not bus['trailing_detail']
    summaries = {name:parser.summary(data['frames']) for name,data in [('d0',d0),('d1',d1)]}
    for data in [d0,d1]:
        assert all(not data[k] for k in ['warnings','byte_issues','bad_checksums','gaps'])
        assert not parser.summary(data['frames'])['sequence_errors']
        assert data['oracle']['discarded_bytes']==0
    inputs,replies = d0['frames'],d1['frames']
    assert inputs[0]['seq']==replies[0]['seq']==0
    assert len(inputs)==len(replies)+1
    assert d0['oracle']['trailing_bytes']==0 and d1['oracle']['trailing_bytes']==6
    # 末包只剩采集右边界的六个完整字节及下个字节部分位，不算中途丢包。
    suffix=bytes(item['byte'] for item in d1['skipped'])
    assert len(suffix)==6 and suffix[:3]==bytes([0xA5,0x5A,inputs[-1]['seq']])
    assert min(item['time'] for item in d1['skipped'])>replies[-1]['end']
    startup = [t for t in bus['transactions'] if t['register'] not in ['3A','3B']]
    reads = {t['register']:t['data'] for t in startup if t['mode']=='read'}
    assert reads=={'75':'68','6B':'01','1A':'02','19':'03','1C':'00','38':'01'}
    params_path=ROOT/'report/mpu6050_calibration_params_20261101.json'
    params=json.loads(params_path.read_text(encoding='utf-8'))
    bursts=[t for t in bus['transactions'] if t['register']=='3B' and t['mode']=='read']
    assert len(bursts)==len(inputs)
    calibration_mismatches=[]
    sensor_delays=[]
    for n,(source,frame) in enumerate(zip(bursts,inputs)):
        expected=calibrated(source['data'],params)
        if frame['axes']!=expected:calibration_mismatches.append({'index':n,'expected':expected,'observed':frame['axes']})
        assert 0<frame['time']-source['end']<0.001
        sensor_delays.append((frame['time']-source['end'])*1e6)
    mem=ROOT/'data/reference/stage4/fir_lp_63_q16.mem'
    manifest=json.loads((ROOT/'build/release/v1.0-rc1/source_manifest.json').read_text(encoding='utf-8'))
    assert fingerprint(mem)==manifest['files'][str(mem.relative_to(ROOT)).replace('\\','/')]
    coeff=[int(s,16) for s in mem.read_text().splitlines() if s.strip()]
    coeff=[v-(1<<18) if v&(1<<17) else v for v in coeff]
    assert len(coeff)==63 and sum(coeff)==65536
    # 记录前段无输入且持续大于12ms，已有流会超时重建；全新流也从首样本建基线。
    assert inputs[0]['time']>0.012 and d0['bytes']==10*len(inputs)
    internal=[]
    for a in range(3):
        values=[f['axes'][a] for f in inputs]
        dc=[0]+dc_sequence(values[1:],values[0]<<16)
        internal.append(fir(dc,coeff))
    # 复用既有设计参考并用NumPy独立卷积复核，避免单份新脚本自证。
    import numpy as np
    from host.stage4_reference import dc_fixed, fir_fixed, round_away, saturate
    for a in range(3):
        dc=dc_fixed([f['axes'][a] for f in inputs])
        old_reference,_=fir_fixed(dc,coeff)
        convolution=np.convolve(np.asarray(dc,dtype=np.int64),np.asarray(coeff,dtype=np.int64))[:len(dc)]
        independent=[saturate(round_away(int(value),16),18) for value in convolution]
        assert internal[a]==old_reference==independent
    mismatches=[];max_error=[0,0,0];delays=[]
    for n,reply in enumerate(replies):
        assert inputs[n]['seq']==reply['seq']
        delays.append((reply['time']-inputs[n]['time'])*1e6)
        assert 0<delays[-1]<2000
        expected=[internal[a][n]>>2 for a in range(3)]
        if expected!=reply['axes']:mismatches.append({'index':n,'expected':expected,'observed':reply['axes']})
        for a in range(3):max_error[a]=max(max_error[a],abs(expected[a]-reply['axes'][a]))
    last=inputs[-1];last_values=[internal[a][-1]>>2 for a in range(3)]
    from host.protocol import encode, Sample
    expected_tail=encode(Sample(last['seq'],*last_values))
    assert suffix==expected_tail[:6]
    windows=[]
    for begin in range(62,len(inputs)-127,128):
        axes=[[internal[a][j] for j in range(begin,begin+128)] for a in range(3)]
        ms=[sum(v*v for v in axis)//128 for axis in axes]
        windows.append({'index':len(windows),'first_seq':inputs[begin]['seq'],'last_seq':inputs[begin+127]['seq'],
                        'first_input_time_s':inputs[begin]['time'],'last_input_time_s':inputs[begin+127]['time'],
                        'predicted_ms':ms,'predicted_rms':[math.isqrt(v) for v in ms],
                        'predicted_peak':[max(map(abs,axis)) for axis in axes]})
    # 这些窗口只来自已验证回传的数值模型，没有作为本次实测ILA窗口。
    bins=[]
    for begin in range(0,20,2):
        fi=[f for f in inputs if begin<=f['time']<begin+2]
        fo=[f for f in replies if begin<=f['time']<begin+2]
        bins.append({'start_s':begin,'end_s':begin+2,'input':stats(fi),'restored_output':stats(fo,4),
                     'restored_output_rms':[math.sqrt(statistics.mean((f['axes'][a]*4)**2 for f in fo)) for a in range(3)]})
    # 以下为实际打开PNG后人工转录的十六进制值，截图发生于本次STM32复位之前。
    screenshot={'file':'ila_3.png','source':'人工审阅PNG，未提供原始ILA CSV；与后续UART非同一采集时段',
                'before':{'window_id':0x8AC,'seq_start':0x3E,'seq_end':0xBD,'ms':[0x23D,0x202,0x392],
                          'rms':[0x17,0x16,0x1E],'peak':[0x36,0x3E,0x4B]},
                'after':{'window_id':0x8AD,'seq_start':0xBE,'seq_end':0x3D,'ms':[0x4E5,0x1A7A,0x36CD],
                         'rms':[0x23,0x52,0x76],'peak':[0xA9,0x158,0x226]},
                'quality_valid':1,'alarm_valid':1,'alarm_axes':0,'dropped_count':0,
                'filter_restart_count':6,'aborted_windows':6,
                'rx_frame_count_before':0x45AA4,'rx_frame_count_after':0x45AA5,'completed_count':0x45AA4,
                'feature_valid_at_start_cursor':0,'full_b08_validation_pass':False}
    for state in [screenshot['before'],screenshot['after']]:
        assert (state['seq_end']-state['seq_start'])%256==127
        assert state['rms']==[math.isqrt(v) for v in state['ms']]
        assert all(p*p>=ms for p,ms in zip(state['peak'],state['ms']))
    assert screenshot['after']['window_id']==screenshot['before']['window_id']+1
    assert (screenshot['before']['seq_end']+1)%256==screenshot['after']['seq_start']
    with (OUT/'comparison.csv').open('w',encoding='utf-8',newline='') as stream:
        writer=csv.writer(stream)
        writer.writerow(['index','input_time_s','seq','input_x','input_y','input_z','reference_fir_x','reference_fir_y','reference_fir_z',
                         'expected_wire_x','expected_wire_y','expected_wire_z','measured_wire_x','measured_wire_y','measured_wire_z','complete_reply'])
        for n,frame in enumerate(inputs):
            expected=[internal[a][n]>>2 for a in range(3)]
            writer.writerow([n,frame['time'],frame['seq'],*frame['axes'],*[internal[a][n] for a in range(3)],*expected,
                             *(replies[n]['axes'] if n<len(replies) else ['','','']),int(n<len(replies))])
    result={'original_sha256':hashes,'archive_crc_ok':True,'settings':settings,'startup_i2c':startup,
            'startup_register_readbacks':reads,'i2c_transactions':len(bus['transactions']),
            'i2c_register_counts':dict(parser.Counter(t['register'] for t in bus['transactions'])),
            'i2c_complete_axis_reads':len(bursts),'i2c_problems':bus['problems'],
            'calibration_id':params['calibration_id'],'parameter_sha256':fingerprint(params_path),'coefficient_sha256':fingerprint(mem),
            'calibration_checked_frames':len(inputs),'calibration_mismatches':calibration_mismatches,
            'd0_summary':summaries['d0'],'d1_summary':summaries['d1'],
            'd0_checks':{k:v for k,v in d0.items() if k not in ['frames','groups']},
            'd1_checks':{k:v for k,v in d1.items() if k not in ['frames','groups']},
            'reference':{'start_assumption':'输入首包前无串口数据超过12ms，按已核对RTL断流重建规则首包建基线/历史；并非FPGA全局复位',
                         'first_input_time_s':inputs[0]['time'],'first_seq':inputs[0]['seq'],'reconstructed_inputs':0,
                         'checked_frames':len(replies),'skipped_warmup_frames':0,'max_wire_error':max_error,'mismatches':mismatches,
                         'existing_stage4_reference_and_numpy_convolution_match':True,
                         'predicted_last_wire_axes':last_values,'last_captured_prefix_hex':suffix.hex(' ').upper(),
                         'last_prefix_matches_reference':True,'complete_filter_uart_pass':not mismatches},
            'input_to_reply_us':{'mean':statistics.mean(delays),'min':min(delays),'max':max(delays)},
            'i2c_to_input_us':{'mean':statistics.mean(sensor_delays),'min':min(sensor_delays),'max':max(sensor_delays)},
            'time_bins_2s':bins,'predicted_windows_not_measured_ila':windows,
            'ila_screenshot_manual_review':screenshot,'fpga_global_reset_observed':False,'full_b08_alarm_validation_pass':False}
    (OUT/'analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    assert not calibration_mismatches and not mismatches
    assert all(fingerprint(BASE/name)==value for name,value in hashes.items())
    print(json.dumps({'frames':[len(inputs),len(replies)],'calibration_matches':len(inputs),'reference':result['reference'],
                      'intervals':{key:summaries['d0'][key] for key in ['interval_mean_ms','interval_min_ms','interval_max_ms','rate_over_span_hz']},
                      'short_intervals':len(summaries['d0']['interval_outliers']),'bins':bins,
                      'predicted_window_count':len(windows),'max_predicted_window_rms':[max(w['predicted_rms'][a] for w in windows) for a in range(3)],
                      'ila':screenshot,'latency':result['input_to_reply_us']},ensure_ascii=False))
    print('PASS filter_test_3_analysis originals_unchanged')


if __name__=='__main__':
    main()
