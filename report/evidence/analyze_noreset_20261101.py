"""核查三份无复位长记录及Z轴两点初值，不改原始文件或校准参数。"""

import bisect
import csv
import hashlib
import json
from pathlib import Path
import statistics
import zipfile

import analyze_session_20261101 as parser

ROOT = parser.ROOT
BASE = ROOT / 'report/evidence/20261101_session01'
OUT = ROOT / 'report/evidence/20261101_noreset_analysis'
SOURCES = {
    '60s': ('60s.atkdl', 'uart_d0_60s.csv', 'usart_d1_60s.csv', 'i2c_60s.csv'),
    'noreset_zp': ('init_raw_noreset_zp.atkdl', 'init_d0_uart_noreset_zp.csv',
                   'init_d1_uart_noreset_zp.csv', 'init_i2c_noreset_zp.csv'),
    'noreset_zn': ('init_raw_noreset_zn.atkdl', 'init_d0_uart_noreset_zn.csv',
                   'init_d1_uart_noreset_zn.csv', 'init_i2c_noreset_zn.csv'),
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def analyze(label, names):
    directory = BASE / label
    parser.BASE = directory
    archive, d0_name, d1_name, i2c_name = names
    hashes = {p.name: sha(p) for p in directory.iterdir() if p.is_file()}
    with zipfile.ZipFile(directory / archive) as z:
        assert z.testzip() is None
        config = dict(line.split('=', 1) for line in z.read('set.ini').decode('utf-8-sig').splitlines() if '=' in line)
        settings = json.loads(config['settingData'])
        enabled = [c['id'] for c in json.loads(config['channelsSet']) if c['enable']]
    d0, d1 = parser.uart(d0_name), parser.uart(d1_name)
    # 先核查导出类型，防止把错误命名的UART文件当成I2C证据。
    first_i2c_row = next(parser.rows(i2c_name))
    i2c_valid = first_i2c_row['kind'] in ('Bits', 'Address/data', 'Packets')
    bus = parser.i2c(i2c_name) if i2c_valid else None
    replies = d1['frames']
    reply_times = [f['time'] for f in replies]
    bursts = [t for t in bus['transactions'] if t['mode'] == 'read' and t['register'] == '3B'] if bus else []
    burst_ends = [t['end'] for t in bursts]
    reply_failures, sensor_failures, matched_reply_indices, matched_burst_indices, delays = [], [], set(), set(), []
    for f in d0['frames']:
        j = bisect.bisect_left(reply_times, f['time'])
        candidates = [k for k in range(j, min(j + 3, len(replies)))
                      if 0 <= replies[k]['time'] - f['time'] < 0.003 and replies[k]['hex'] == f['hex']]
        if len(candidates) == 1:
            k = candidates[0]
            assert k not in matched_reply_indices
            matched_reply_indices.add(k)
            delays.append((replies[k]['time'] - f['time']) * 1e6)
        else:
            reply_failures.append(f)
        if bus:
            i = bisect.bisect_right(burst_ends, f['time']) - 1
            if i >= 0 and f['time'] - bursts[i]['end'] < 100e-6 and f['payload'] == bursts[i]['data']:
                assert i not in matched_burst_indices
                matched_burst_indices.add(i)
            else:
                sensor_failures.append(f)
    # 边界候选单独记录，不把时间窗外缺少配对的首尾包当内部故障。
    boundary_i2c = [f for f in sensor_failures if bursts and f['time'] < bursts[0]['end']]
    boundary_replies = [f for f in reply_failures if replies and f['end'] >= replies[-1]['end']]
    unmatched_d1 = [f for n, f in enumerate(replies) if n not in matched_reply_indices]
    boundary_d1 = [f for f in unmatched_d1 if f['time'] < d0['frames'][0]['time']]
    summaries = [parser.summary(g) for g in d0['groups']]
    outliers = [o for s in summaries for o in s['interval_outliers']]
    spacings = [b['time'] - a['time'] for a, b in zip(outliers, outliers[1:])]
    windows = []
    for second in range(0, int(settings['setTime'] / 1000), 5):
        group = [f for f in d0['frames'] if second <= f['time'] < second + 5]
        if len(group) > 1:
            windows.append({'from_s': second, 'to_s': second + 5, 'count': len(group),
                            'mean': [statistics.mean(f['axes'][i] for f in group) for i in range(3)],
                            'std': [statistics.stdev(f['axes'][i] for f in group) for i in range(3)]})
    # 此阈值仅用于定位瞬态，不作为器件规格或删样规则。
    median_z = statistics.median(f['axes'][2] for f in d0['frames'])
    transient_frames = [f for f in d0['frames'] if abs(f['axes'][2] - median_z) > 500]
    transient_groups = []
    for frame in transient_frames:
        if not transient_groups or frame['time'] - transient_groups[-1][-1]['time'] > 0.1:
            transient_groups.append([])
        transient_groups[-1].append(frame)
    transient_summary = {'reference_median_counts': median_z, 'deviation_threshold_counts': 500,
                         'group_join_gap_s': 0.1, 'count': len(transient_frames),
                         'groups': [{'first_s': g[0]['time'], 'last_s': g[-1]['time'], 'count': len(g),
                                     'min_z': min(f['axes'][2] for f in g),
                                     'max_z': max(f['axes'][2] for f in g)} for g in transient_groups],
                         'samples_removed': False}
    result = {
        'original_sha256': hashes, 'settings': settings, 'enabled_channels': enabled, 'archive_crc_ok': True,
        'd0': {k: v for k, v in d0.items() if k not in ('frames', 'groups')},
        'd1': {k: v for k, v in d1.items() if k not in ('frames', 'groups')},
        'd0_segments': summaries, 'd1_segments': [parser.summary(g) for g in d1['groups']],
        'i2c_export_valid': i2c_valid, 'i2c_matches_d0_file': hashes[i2c_name] == hashes[d0_name],
        'i2c_complete_transactions': len(bus['transactions']) if bus else None,
        'i2c_problems': bus['problems'] if bus else None,
        'i2c_boundary_packets': bus['partial_packets'] if bus else None,
        'i2c_register_counts': dict(parser.Counter(t['register'] for t in bus['transactions'])) if bus else None,
        'i2c_accel_bursts': len(bursts) if bus else None, 'i2c_matched': len(matched_burst_indices) if bus else None,
        'sensor_failures': sensor_failures, 'sensor_boundary_unmatched': boundary_i2c,
        'reply_matches': len(matched_reply_indices), 'reply_failures': reply_failures,
        'reply_boundary_unmatched': boundary_replies, 'unmatched_d1': unmatched_d1,
        'd1_boundary_unmatched': boundary_d1,
        'reply_delay_us': {'mean': statistics.mean(delays), 'min': min(delays), 'max': max(delays)},
        'outlier_spacing_s': {'mean': statistics.mean(spacings), 'min': min(spacings), 'max': max(spacings)} if spacings else None,
        'five_second_windows': windows,
        'z_transient_locator': transient_summary,
        'd0_interior_warnings': [w for w in d0['warnings'] if d0['frames'][0]['time'] <= w['time'] <= d0['frames'][-1]['end']],
    }
    with (OUT / f'{label}_frames.csv').open('w', encoding='utf-8', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['time_s', 'seq', 'x', 'y', 'z'])
        for f in d0['frames']:
            writer.writerow([f['time'], f['seq'], *f['axes']])
    assert all(sha(directory / name) == digest for name, digest in hashes.items())
    (OUT / f'{label}.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    compact = {k: v for k, v in result.items() if k not in ('d0', 'd1', 'd0_segments', 'd1_segments', 'original_sha256', 'five_second_windows')}
    compact['d0_segments'] = [{**s, 'interval_outliers': len(s['interval_outliers'])} for s in summaries]
    compact['boundary_bytes'] = [d0['skipped'], d1['skipped']]
    compact['uart_issues'] = {c: {k: len(data[k]) for k in ['byte_issues', 'warnings', 'bad_checksums']} for c, data in [('d0', d0), ('d1', d1)]}
    print(label, json.dumps(compact, ensure_ascii=False), flush=True)
    return result, d0['frames']


def main():
    OUT.mkdir(exist_ok=True)
    results, frames = {}, {}
    for label, names in SOURCES.items():
        results[label], frames[label] = analyze(label, names)
    zp, zn = (results[k]['d0_segments'][0]['mean'][2] for k in ['noreset_zp', 'noreset_zn'])
    bias = (zp + zn) / 2
    sensitivity = (zp - zn) / 2
    fit = {'bias_z_counts': bias, 'sensitivity_z_counts_per_g': sensitivity, 'gain_z': 16384 / sensitivity,
           'formal_calibration_pass': False, 'note': '仅Z正反面两点初值，不能替代完整六面与独立第二轮'}
    fit['user_60s_stationarity_confirmation'] = '全程固定静止，未主动触碰；不得自动将瞬态归因为人为操作'
    for label, values in frames.items():
        corrected = [(f['axes'][2] - bias) / sensitivity for f in values]
        fit[label] = {'corrected_z_mean_g': statistics.mean(corrected),
                      'corrected_z_std_g': statistics.stdev(corrected),
                      'independent_full_calibration_validation': False}
    (OUT / 'z_pair_fit.json').write_text(json.dumps(fit, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Z_PAIR', json.dumps(fit, ensure_ascii=False))
    print('PASS noreset_analysis originals_unchanged formal_calibration_pass=false')


if __name__ == '__main__':
    main()
