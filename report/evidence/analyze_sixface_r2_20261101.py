"""用固定第一轮参数独立验证第二轮六面，不修改参数或固件。"""

import csv
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import statistics
import zipfile

import analyze_noreset_20261101 as capture

ROOT = capture.ROOT
OUT = ROOT / 'report/evidence/20261101_sixface_r2_analysis'
R1_PATH = ROOT / 'report/evidence/20261101_sixface_r1_analysis/sixface_fit.json'


def main(source_suffixes=None):
    OUT.mkdir(exist_ok=True)
    r1_hash = capture.sha(R1_PATH)
    r1 = json.loads(R1_PATH.read_text(encoding='utf-8'))
    # 使用第一轮留存的精确参数，禁止以本轮拟合值替换验证参数。
    bias = [Fraction(v) for v in r1['exact_bias']]
    sensitivity = [Fraction(v) for v in r1['exact_sensitivity']]
    capture.OUT = OUT
    suffixes = source_suffixes or {pose: pose+'_r2' for pose in ['xp','xn','yp','yn','zp','zn']}
    results, samples = {}, {}
    for pose in ['xp', 'xn', 'yp', 'yn', 'zp', 'zn']:
        label = pose + '_r2'
        suffix = suffixes[pose]
        names = (f'init_raw_{suffix}.atkdl', f'init_uart_d0_{suffix}.csv',
                 f'init_uart_d1_{suffix}.csv', f'init_i2c_{suffix}.csv')
        results[pose], samples[pose] = capture.analyze(label, names)
    duplicate_pairs = []
    invalid_poses = set()
    for n, pose in enumerate(samples):
        for previous in list(samples)[:n]:
            a = results[pose]['original_sha256'][f'init_uart_d0_{suffixes[pose]}.csv']
            b = results[previous]['original_sha256'][f'init_uart_d0_{suffixes[previous]}.csv']
            if a == b:
                wave_hashes = {}
                for item in [previous, pose]:
                    path = capture.BASE / (item + '_r2') / f'init_raw_{suffixes[item]}.atkdl'
                    with zipfile.ZipFile(path) as archive:
                        channels = {}
                        for channel in range(4):
                            digest = hashlib.sha256()
                            names = sorted(name for name in archive.namelist() if name.startswith(str(channel)+'/') and name.endswith('.bin'))
                            for name in names:
                                digest.update(name.encode());digest.update(archive.read(name))
                            channels[str(channel)] = digest.hexdigest()
                        wave_hashes[item] = channels
                same_waveform = wave_hashes[previous] == wave_hashes[pose]
                duplicate_pairs.append({'first': previous, 'second': pose, 'identical_d0_csv': True,
                                        'same_four_channel_waveform': same_waveform, 'waveform_sha256': wave_hashes})
                invalid_poses.add(pose)
    means = {p: [Fraction(sum(f['axes'][i] for f in frames), len(frames)) for i in range(3)]
             for p, frames in samples.items()}
    r2_bias, r2_sensitivity = [], []
    for i, axis in enumerate('xyz'):
        positive, negative = means[axis + 'p'][i], means[axis + 'n'][i]
        r2_bias.append((positive + negative) / 2)
        r2_sensitivity.append((positive - negative) / 2)
    assessable = [axis+'p' not in invalid_poses and axis+'n' not in invalid_poses for axis in 'xyz']
    repeat = {'axes_assessable': dict(zip('xyz',assessable)),
              'r2_bias_for_diagnosis_only': [float(v) if ok else None for v,ok in zip(r2_bias,assessable)],
              'r2_sensitivity_for_diagnosis_only': [float(v) if ok else None for v,ok in zip(r2_sensitivity,assessable)],
              'bias_difference_counts': [float(b - a) if ok else None for a,b,ok in zip(bias,r2_bias,assessable)],
              'sensitivity_difference_percent': [float((b-a)/a*100) if ok else None for a,b,ok in zip(sensitivity,r2_sensitivity,assessable)]}
    repeat['bias_repeatability_within_164_counts'] = (all(abs(v) <= 164 for v in repeat['bias_difference_counts']) if all(assessable) else None)
    repeat['sensitivity_repeatability_within_1_percent'] = (all(abs(v) <= 1 for v in repeat['sensitivity_difference_percent']) if all(assessable) else None)
    output = {'scope': '固定第一轮参数的第二轮独立离线验证', 'formal_calibration_pass': False,
              'r1_parameter_file': str(R1_PATH.relative_to(ROOT)), 'r1_sha256': r1_hash,
              'fixed_bias_counts': list(map(float, bias)), 'fixed_sensitivity_counts_per_g': list(map(float, sensitivity)),
              'repeatability': repeat, 'poses': {}, 'criteria_are_project_suggestions_not_device_guarantees': True,
              'duplicate_pairs': duplicate_pairs, 'invalid_poses': sorted(invalid_poses),
              'validation_dataset_complete': not invalid_poses, 'selected_file_suffixes': suffixes}
    for pose, frames in samples.items():
        axis = 'xyz'.index(pose[0]);target = 1 if pose[1] == 'p' else -1
        corrected = [[float((Fraction(v) - bias[i]) / sensitivity[i]) for i, v in enumerate(f['axes'])] for f in frames]
        norm = [math.sqrt(sum(v*v for v in row)) for row in corrected]
        mean = [statistics.mean(row[i] for row in corrected) for i in range(3)]
        exact_mean = [float((means[pose][i] - bias[i]) / sensitivity[i]) for i in range(3)]
        assert max(abs(a-b) for a,b in zip(mean,exact_mean)) < 1e-12
        main_error = abs(mean[axis] - target)
        cross = max(abs(mean[i]) for i in range(3) if i != axis)
        r = results[pose]
        interior_reply = len(r['reply_failures']) - len(r['reply_boundary_unmatched'])
        interior_d1 = len(r['unmatched_d1']) - len(r['d1_boundary_unmatched'])
        interior_i2c = len(r['sensor_failures']) - len(r['sensor_boundary_unmatched'])
        communication_ok = (r['i2c_export_valid'] and not r['i2c_problems'] and not r['d0_interior_warnings']
                            and not interior_reply and not interior_d1 and not interior_i2c
                            and all(not s['sequence_errors'] for s in r['d0_segments'])
                            and all(not r[c]['bad_checksums'] for c in ['d0','d1']))
        median = statistics.median(f['axes'][axis] for f in frames)
        transient = [f for f in frames if abs(f['axes'][axis] - median) > 500]
        groups = []
        for f in transient:
            if not groups or f['time'] - groups[-1][-1]['time'] > 0.1:
                groups.append([])
            groups[-1].append(f)
        entry = {'source_suffix': suffixes[pose], 'raw_segments': r['d0_segments'], 'corrected_mean_g': mean,
                 'corrected_std_g': [statistics.stdev(row[i] for row in corrected) for i in range(3)],
                 'corrected_norm_mean_g': statistics.mean(norm), 'corrected_norm_std_g': statistics.stdev(norm),
                 'corrected_norm_min_g': min(norm), 'corrected_norm_max_g': max(norm),
                 'main_axis_mean_error_g': main_error, 'cross_axis_max_mean_g': cross,
                 'main_axis_mean_pass': main_error <= 0.05, 'cross_axis_mean_pass': cross <= 0.05,
                 'norm_mean_pass': 0.97 <= statistics.mean(norm) <= 1.03,
                 'capture_duration_pass': r['settings']['setTime'] >= 20000,
                 'communication_comparable_region_pass': communication_ok,
                 'uart_matches': r['reply_matches'], 'i2c_matches': r['i2c_matched'],
                 'interior_unmatched': {'reply': interior_reply,'extra_reply':interior_d1,'i2c':interior_i2c},
                 'main_axis_transient_locator': {'threshold_counts':500,'median_counts':median,'count':len(transient),
                     'groups':[{'first_s':g[0]['time'],'last_s':g[-1]['time'],'count':len(g),
                                'min':min(f['axes'][axis] for f in g),'max':max(f['axes'][axis] for f in g)} for g in groups]},
                 'samples_removed': False}
        entry['pose_record_valid'] = pose not in invalid_poses
        entry['suggested_mean_criteria_pass'] = (entry['main_axis_mean_pass'] and entry['cross_axis_mean_pass'] and entry['norm_mean_pass']) if entry['pose_record_valid'] else None
        output['poses'][pose] = entry
        with (OUT / f'{pose}_r2_corrected.csv').open('w',encoding='utf-8',newline='') as stream:
            writer=csv.writer(stream);writer.writerow(['time_s','seq','raw_x','raw_y','raw_z','x_g','y_g','z_g','norm_g'])
            for f, values, magnitude in zip(frames,corrected,norm):writer.writerow([f['time'],f['seq'],*f['axes'],*values,magnitude])
        print('R2_POSE',pose,json.dumps({k:v for k,v in entry.items() if k!='raw_segments'},ensure_ascii=False),flush=True)
    output['all_suggested_mean_criteria_pass'] = output['validation_dataset_complete'] and all(p['suggested_mean_criteria_pass'] for p in output['poses'].values())
    output['all_comparable_communication_pass'] = all(p['communication_comparable_region_pass'] for p in output['poses'].values())
    output['repeatability_suggested_criteria_pass'] = (repeat['bias_repeatability_within_164_counts'] and repeat['sensitivity_repeatability_within_1_percent']) if all(assessable) else None
    assert capture.sha(R1_PATH) == r1_hash
    for pose,r in results.items():
        assert all(capture.sha(capture.BASE/(pose+'_r2')/n)==h for n,h in r['original_sha256'].items())
    (OUT/'r2_validation.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('REPEATABILITY',json.dumps(repeat,ensure_ascii=False))
    print('SUMMARY',json.dumps({k:output[k] for k in ['all_suggested_mean_criteria_pass','all_comparable_communication_pass','repeatability_suggested_criteria_pass','formal_calibration_pass']},ensure_ascii=False))
    print('PASS r2_analysis_completed originals_and_r1_parameters_unchanged')


if __name__ == '__main__':
    main()
