"""复核补采姿态并保留旧第二轮结果，沿用第一轮固定参数。"""

import analyze_sixface_r2_20261101 as validation


if __name__ == '__main__':
    validation.OUT = validation.ROOT / 'report/evidence/20261101_sixface_r2b_analysis'
    validation.main({'xp':'xp_r2b','xn':'xn_r2b','yp':'yp_r2',
                     'yn':'yn_r2','zp':'zp_r2','zn':'zn_r2b'})
