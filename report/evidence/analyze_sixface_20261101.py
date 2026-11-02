"""分析同条件第一轮六面长记录；只输出离线初值，不改固件参数。"""

import csv
from fractions import Fraction
import json
import math
from pathlib import Path
import statistics

import analyze_noreset_20261101 as capture

ROOT = capture.ROOT
OUT = ROOT / 'report/evidence/20261101_sixface_r1_analysis'


def main():
    OUT.mkdir(exist_ok=True)
    capture.OUT = OUT
    sources = {f'noreset_{p}': (f'init_raw_{p}.atkdl', f'init_uart_d0_{p}.csv',
                               f'init_uart_d1_{p}.csv', f'init_i2c_{p}.csv')
               for p in ['xp', 'xn', 'yp', 'yn']}
    sources.update({p: capture.SOURCES[p] for p in ['noreset_zp', 'noreset_zn']})
    results, samples = {}, {}
    for label, names in sources.items():
        results[label], samples[label] = capture.analyze(label, names)
    # 用精确有理数从每轴对应正反面均值推导，另核对浮点表达。
    means = {pose: [Fraction(sum(f['axes'][i] for f in frames), len(frames)) for i in range(3)]
             for pose, frames in samples.items()}
    bias, sensitivity, gain = [], [], []
    for i, axis in enumerate('xyz'):
        positive, negative = means[f'noreset_{axis}p'][i], means[f'noreset_{axis}n'][i]
        b, s = (positive + negative) / 2, (positive - negative) / 2
        assert s > 0
        bias.append(b);sensitivity.append(s);gain.append(Fraction(16384) / s)
    fit = {'status': 'FIRST_ROUND_OFFLINE_INITIAL_VALUES', 'formal_calibration_pass': False,
           'independent_second_round_available': False,
           'user_confirmation': '同一模块、同一原SensorSource固件和配置，摆稳后静止采集',
           'bias_counts': list(map(float, bias)), 'sensitivity_counts_per_g': list(map(float, sensitivity)),
           'gain': list(map(float, gain)),
           'exact_bias': list(map(str, bias)), 'exact_sensitivity': list(map(str, sensitivity)),
           'poses': {}, 'original_sha256': {p: r['original_sha256'] for p, r in results.items()}}
    for pose, frames in samples.items():
        axis = 'xyz'.index(pose[-2]);target = 1 if pose[-1] == 'p' else -1
        corrected = [[(f['axes'][i] - float(bias[i])) / float(sensitivity[i]) for i in range(3)] for f in frames]
        norm = [math.sqrt(sum(v*v for v in row)) for row in corrected]
        corrected_mean = [statistics.mean(row[i] for row in corrected) for i in range(3)]
        exact_corrected_mean = [float((means[pose][i] - bias[i]) / sensitivity[i]) for i in range(3)]
        assert max(abs(a-b) for a,b in zip(corrected_mean, exact_corrected_mean)) < 1e-12
        assert abs(corrected_mean[axis] - target) < 1e-12
        cross = max(abs(corrected_mean[i]) for i in range(3) if i != axis)
        median = statistics.median(f['axes'][axis] for f in frames)
        transient = [f for f in frames if abs(f['axes'][axis] - median) > 500]
        groups = []
        for f in transient:
            if not groups or f['time'] - groups[-1][-1]['time'] > 0.1:
                groups.append([])
            groups[-1].append(f)
        r = results[pose]
        entry = {'raw_summary': r['d0_segments'], 'corrected_mean_g': corrected_mean,
                 'corrected_std_g': [statistics.stdev(row[i] for row in corrected) for i in range(3)],
                 'corrected_norm_mean_g': statistics.mean(norm), 'corrected_norm_std_g': statistics.stdev(norm),
                 'max_cross_axis_mean_g': cross, 'same_data_fit_not_independent_validation': True,
                 'fit_nonmain_axis_within_suggested_0p05g': cross <= 0.05,
                 'fit_norm_mean_within_suggested_range': 0.97 <= statistics.mean(norm) <= 1.03,
                 'main_axis_transient_locator': {'axis': 'xyz'[axis], 'median': median, 'threshold_counts': 500,
                     'count': len(transient), 'samples_removed': False,
                     'groups': [{'start_s': g[0]['time'], 'end_s': g[-1]['time'], 'count': len(g),
                                 'min_main': min(f['axes'][axis] for f in g),
                                 'max_main': max(f['axes'][axis] for f in g)} for g in groups]},
                 'uart_pair_matches': r['reply_matches'],
                 'uart_interior_unmatched': len(r['reply_failures']) - len(r['reply_boundary_unmatched']),
                 'd1_interior_unmatched': len(r['unmatched_d1']) - len(r['d1_boundary_unmatched']),
                 'i2c_pair_matches': r['i2c_matched'], 'i2c_export_valid': r['i2c_export_valid'],
                 'i2c_interior_unmatched': len(r['sensor_failures']) - len(r['sensor_boundary_unmatched']),
                 'i2c_problems': len(r['i2c_problems']) if r['i2c_problems'] is not None else None,
                 'uart_interior_warnings': r['d0_interior_warnings']}
        fit['poses'][pose] = entry
        with (OUT / f'{pose}_corrected.csv').open('w', encoding='utf-8', newline='') as stream:
            writer = csv.writer(stream);writer.writerow(['time_s', 'seq', 'raw_x', 'raw_y', 'raw_z', 'x_g', 'y_g', 'z_g', 'norm_g'])
            for f, values, magnitude in zip(frames, corrected, norm):
                writer.writerow([f['time'], f['seq'], *f['axes'], *values, magnitude])
        print('FIT_POSE',pose,json.dumps({k:v for k,v in entry.items() if k!='raw_summary'},ensure_ascii=False),flush=True)
    # 验证全部24份输入在计算校准过程中没有被改动。
    for pose, hashes in fit['original_sha256'].items():
        assert all(capture.sha(capture.BASE / pose / n) == h for n,h in hashes.items())
    (OUT / 'sixface_fit.json').write_text(json.dumps(fit,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('COEFFICIENTS',json.dumps({k:fit[k] for k in ['bias_counts','sensitivity_counts_per_g','gain']},ensure_ascii=False))
    print('PASS sixface_analysis originals_unchanged formal_calibration_pass=false')


if __name__ == '__main__':
    main()
