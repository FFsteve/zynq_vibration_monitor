// 参数依据：第一轮六面静止数据估计偏置/比例，再用独立r2/r2b记录检查项目静态指标。
// 最终校准目标已完成后续链路核验；历史与范围见report/calibration_firmware_update_20261101.md。
// 三个数组元素始终按X、Y、Z顺序；bias单位是原始计数乘65536，gain是无量纲比例乘65536。
// 量化后增益约为1.00464、0.99457、0.97804；运行时只做整数运算，不在每次采样时拟合参数。
// 本组常量绑定当前这颗MPU6050及配置；更换模块、量程或偏置条件后不可直接宣称仍有效。
// 更新参数应保留来源数据和独立验证，不能用同一批数据拟合后再把拟合误差当泛化效果。

/* 第一轮六面20秒参数，已通过独立记录的项目静态离线指标；后续校准链路验证见报告。 */
/* 第一轮输入集合SHA256：de0ba0a3da42483f7220c3f6d7a648f1d3c3457aef4a689709ba393692ebd4c5 */
/* 参数来源与独立验证指纹见report/mpu6050_calibration_params_20261101.json。 */
#ifndef ACCEL_CALIBRATION_PARAMS_H
#define ACCEL_CALIBRATION_PARAMS_H
#include <stdint.h>
#define ACCEL_CALIBRATION_ID "sixface_r1_20261101_validated"
// 偏置先在Q16域扣除，保留亚计数精度；不能先取整到整数计数再校准。
static const int32_t accel_bias_q16[3]={47687499,-36176278,341942451};
// 常量化增益不改变±2g的目标计数尺度；输出仍按16384计数/g解释静态标定值。
static const int32_t accel_gain_q16[3]={65840,65180,64097};
#endif
