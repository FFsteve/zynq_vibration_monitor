/* 第一轮六面20秒参数，已通过独立记录的项目静态离线指标；新固件尚待板测。 */
/* 第一轮输入集合SHA256：de0ba0a3da42483f7220c3f6d7a648f1d3c3457aef4a689709ba393692ebd4c5 */
/* 参数来源与独立验证指纹见report/mpu6050_calibration_params_20261101.json。 */
#ifndef ACCEL_CALIBRATION_PARAMS_H
#define ACCEL_CALIBRATION_PARAMS_H
#include <stdint.h>
#define ACCEL_CALIBRATION_ID "sixface_r1_20261101_validated"
static const int32_t accel_bias_q16[3]={47687499,-36176278,341942451};
static const int32_t accel_gain_q16[3]={65840,65180,64097};
#endif
