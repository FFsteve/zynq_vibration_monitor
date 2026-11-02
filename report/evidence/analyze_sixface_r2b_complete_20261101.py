"""加入Y正面补采，对六面选定记录作固定参数的最终离线复核。"""

import analyze_sixface_r2_20261101 as validation
import json

OUT = validation.ROOT / 'report/evidence/20261101_sixface_r2b_complete_analysis'


def finalize_summary():
    # 离线静态指标和固件落地/整体验收分别记录，避免混用通过范围。
    path = OUT / 'r2_validation.json'
    result = json.loads(path.read_text(encoding='utf-8'))
    result['offline_static_validation_pass'] = (
        result['validation_dataset_complete'] and result['all_suggested_mean_criteria_pass']
        and result['all_comparable_communication_pass'] and result['repeatability_suggested_criteria_pass']
        and all(p['capture_duration_pass'] for p in result['poses'].values()))
    result['validation_stage'] = 'OFFLINE_STATIC_PROJECT_CRITERIA_PASS' if result['offline_static_validation_pass'] else 'OFFLINE_STATIC_PROJECT_CRITERIA_PENDING'
    result['firmware_with_fixed_r1_parameters_tested_on_board'] = False
    path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(result['validation_stage'])


if __name__ == '__main__':
    validation.OUT = OUT
    validation.main({'xp':'xp_r2b','xn':'xn_r2b','yp':'yp_r2b',
                     'yn':'yn_r2','zp':'zp_r2','zn':'zn_r2b'})
    finalize_summary()
