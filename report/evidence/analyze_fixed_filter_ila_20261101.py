"""核查固定源滤波回传及人工审阅的ILA快照，不操作硬件。"""

import hashlib
import json
from pathlib import Path
import statistics
import zipfile

import analyze_session_20261101 as parser

ROOT = parser.ROOT
BASE = ROOT / 'report/evidence/fixed_filter_ila_20261101'
OUT = ROOT / 'report/evidence/fixed_filter_ila_20261101_analysis'


def main():
    OUT.mkdir(exist_ok=True)
    parser.BASE = BASE
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in BASE.iterdir() if p.is_file()}
    with zipfile.ZipFile(BASE/'ila_debug.atkdl') as archive:
        assert archive.testzip() is None
        config = dict(line.split('=',1) for line in archive.read('set.ini').decode('utf-8-sig').splitlines() if '=' in line)
        settings = json.loads(config['settingData'])
    d0 = parser.uart('uart_d0_ila_debug.csv')
    d1 = parser.uart('uart_d1_ila_debug.csv')
    assert len(d0['groups']) == len(d1['groups']) == 1
    assert len(d0['frames']) == len(d1['frames']) == 1250
    delays = []
    for a,b in zip(d0['frames'],d1['frames']):
        assert a['axes'] == [1,-1,-32768]
        assert b['axes'] == [0,0,0] and a['seq'] == b['seq']
        assert bytes.fromhex(b['hex'])[-1] == b['seq']
        delay = (b['time']-a['time'])*1e6
        assert 0 < delay < 2000
        delays.append(delay)
    summaries = {}
    for label,data in [('d0',d0),('d1',d1)]:
        assert all(not data[k] for k in ['byte_issues','warnings','bad_checksums','skipped','gaps'])
        summary = parser.summary(data['frames'])
        assert not summary['sequence_errors'] and not summary['interval_outliers']
        # 固定测试向量有意含signed16最小值，不输出传感器饱和或重力换算结论。
        for key in ['mean_norm_g_at_16384','saturated_samples']:
            summary.pop(key)
        summaries[label] = summary
    # 以下数值为查看原PNG后的人工转录，不伪称来自原始ILA CSV或自动图像识别。
    screenshot = {'file':'ila.png','review_method':'人工查看截图，未提供原始ILA波形数据',
                  'ms_xyz':[0,0,0],'rms_xyz':[0,0,0],'peak_xyz':[0,0,0],
                  'quality_valid':1,'alarm_valid':1,'alarm_axes':0,
                  'window_id_before':0xC1,'window_id_after':0xC2,
                  'seq_before':[0x3E,0xBD],'seq_after':[0xBE,0x3D],
                  'dropped_count':0,'filter_restart_count':2,'aborted_windows':2,
                  'feature_valid_value_at_start_cursor':0,
                  'note':'左值栏光标位于记录开始，红色触发标记在中部；截图不足以自动确认单拍触发或512ms周期'}
    assert all(((end-start)&255)==127 for start,end in [screenshot['seq_before'],screenshot['seq_after']])
    result = {'status':'PASS_FIXED_SOURCE_FILTERED_UART','archive_crc_ok':True,
              'original_sha256':hashes,'settings':settings,'uart_summaries':summaries,
              'matching_packets':1250,'reply_start_delay_us':{'mean':statistics.mean(delays),'min':min(delays),'max':max(delays)},
              'ila_screenshot_manual_review':screenshot,'zero_feature_snapshot_supported':True,
              'full_b08_alarm_validation_pass':False,'new_hardware_operation_by_analysis':False}
    (OUT/'analysis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    assert all(hashlib.sha256((BASE/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
    print(json.dumps({'status':result['status'],'matching_packets':1250,'reply_delay_us':result['reply_start_delay_us'],
                      'd0_interval_ms':[summaries['d0'][k] for k in ['interval_mean_ms','interval_min_ms','interval_max_ms']],
                      'zero_feature_snapshot_supported':True,'full_b08_alarm_validation_pass':False},ensure_ascii=False))
    print('PASS fixed_filter_analysis originals_unchanged')


if __name__ == '__main__':
    main()
