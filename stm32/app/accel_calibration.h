// 校准模块接口与诊断结构；由最终SensorCalibratedTrial目标启用，原始SensorSource保留不启用作对照。
// apply返回XYZ饱和位图，允许原地运算；process额外更新诊断，并原地修改传入三轴。
// clipped_samples统计出现至少一轴饱和的样本数，不是三轴饱和次数之和。
// reset只清诊断，不改变固化校准参数；要更换传感器必须重新测量并更新参数文件。

#ifndef ACCEL_CALIBRATION_H
#define ACCEL_CALIBRATION_H
#include <stdint.h>
// 独立SensorCalibratedTrial目标使用本接口；原始SensorSource不启用。
typedef struct {
    uint32_t samples,clipped_samples;
    int16_t last_raw[3],last_corrected[3];
    uint8_t last_clipped_axes;
} accel_calibration_diagnostics;
extern volatile accel_calibration_diagnostics g_accel_calibration;
// 返回XYZ饱和位图；空指针返回0x80；允许输入输出为同一个数组。
uint8_t accel_calibration_apply(const int16_t raw[3],int16_t corrected[3]);
void accel_calibration_reset(void);
void accel_calibration_process(int16_t axes[3]);
#endif
