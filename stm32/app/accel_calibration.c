#include "accel_calibration.h"
#include "accel_calibration_params.h"
volatile accel_calibration_diagnostics g_accel_calibration;
uint8_t accel_calibration_apply(const int16_t raw[3],int16_t corrected[3])
{
    unsigned axis;
    uint8_t clipped=0;
    if(raw==0 || corrected==0)return 0x80;
    for(axis=0;axis<3;axis++){
        // 两个Q16系数相乘后为Q32；全部中间计算使用64位，不依赖负数右移。
        int64_t product=((int64_t)raw[axis]*65536LL-accel_bias_q16[axis])*accel_gain_q16[axis];
        int64_t value=(product>=0)?(product+2147483648LL)/4294967296LL:
                                     -((-product+2147483648LL)/4294967296LL);
        if(value>32767){value=32767;clipped|=(uint8_t)(1U<<axis);}
        else if(value< -32768){value= -32768;clipped|=(uint8_t)(1U<<axis);}
        corrected[axis]=(int16_t)value;
    }
    return clipped;
}
void accel_calibration_reset(void)
{
    unsigned axis;
    g_accel_calibration.samples=0;g_accel_calibration.clipped_samples=0;
    g_accel_calibration.last_clipped_axes=0;
    for(axis=0;axis<3;axis++){
        g_accel_calibration.last_raw[axis]=0;g_accel_calibration.last_corrected[axis]=0;
    }
}
void accel_calibration_process(int16_t axes[3])
{
    unsigned axis;
    uint8_t mask;
    if(axes==0)return;
    for(axis=0;axis<3;axis++)g_accel_calibration.last_raw[axis]=axes[axis];
    mask=accel_calibration_apply(axes,axes);
    g_accel_calibration.last_clipped_axes=mask;
    if(mask)g_accel_calibration.clipped_samples++;
    g_accel_calibration.samples++;
    for(axis=0;axis<3;axis++)g_accel_calibration.last_corrected[axis]=axes[axis];
}
