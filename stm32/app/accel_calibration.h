#ifndef ACCEL_CALIBRATION_H
#define ACCEL_CALIBRATION_H
#include <stdint.h>
// 本接口仅供实验校准目标使用；原始SensorSource不启用。
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
