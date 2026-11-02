// 校准计算层：对每轴执行corrected = round((raw - bias) * gain)，把结果饱和到signed16。
// bias和gain均使用Q16常量，raw先放大65536后减bias，再乘gain，乘积共带32位小数。
// 用int64_t保存减偏与乘法中间结果，避免Z轴较大偏置或负数极值导致32位溢出。
// 正值加半单位再除2^32，负值先取绝对值再对称恢复符号，恰好半值远离零；不依赖负数右移行为。
// 仅补偿本模块六面测试得到的各轴偏置与比例，不作安装旋转矩阵、温漂或跨轴非正交修正。
// 这是保留重力的传感器校准，不是去直流；PL去直流随后用于提取振动交流量，两者职责不同。
// apply可独立测试，process在其外加诊断记录；是否启用由APP_ACCEL_CALIBRATION控制。

#include "accel_calibration.h"
#include "accel_calibration_params.h"
volatile accel_calibration_diagnostics g_accel_calibration;
uint8_t accel_calibration_apply(const int16_t raw[3],int16_t corrected[3])
{
    unsigned axis;
    uint8_t clipped=0;
    // 0x80单独表示参数错误；低三位只表示XYZ输出饱和，不能把空指针当成正常未饱和。
    if(raw==0 || corrected==0)return 0x80;
    for(axis=0;axis<3;axis++){
        // 两个Q16系数相乘后为Q32；全部中间计算使用64位，不依赖负数右移。
        int64_t product=((int64_t)raw[axis]*65536LL-accel_bias_q16[axis])*accel_gain_q16[axis];
        int64_t value=(product>=0)?(product+2147483648LL)/4294967296LL:
                                     -((-product+2147483648LL)/4294967296LL);
        // 先在64位域比较再截到int16_t；直接强制转换会把过量程正数绕成负数。
        if(value>32767){value=32767;clipped|=(uint8_t)(1U<<axis);}
        else if(value< -32768){value= -32768;clipped|=(uint8_t)(1U<<axis);}
        // 每轴只读取同一轴raw后再写corrected，因此raw与corrected可以是同一数组。
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
// 在覆盖原数组前保存原始值，之后记录校正值与饱和位图，方便Keil同时观察校准前后。
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
