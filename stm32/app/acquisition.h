// 采集层公开接口；与具体STM32寄存器分离，便于用模拟I2C/UART运行主机自检。
// samples表示已取到并组包的样本，tx_packets只统计发送成功，tx_errors与sensor_errors分开定位。
// late_samples记录超过6ms的样本间隔，不能据此计算严格实际采样率或丢失样本总数。
// online表示传感器初始化状态，fixed_source选择测试路径，next_seq是下一次获得样本时使用的序号。
// volatile使调试器可观察实时诊断；它不保证整个结构快照原子一致，也不是线程同步机制。

#ifndef ACQUISITION_H
#define ACQUISITION_H
#include <stdint.h>
typedef struct {
    uint32_t samples,tx_packets,tx_errors,sensor_errors,init_attempts,late_samples;
    uint8_t who_am_i,online,fixed_source,next_seq;
    int16_t last_axes[3];
} acquisition_diagnostics;
extern volatile acquisition_diagnostics g_acquisition;
// 启动时调用一次；fixed_source非0选择固定诊断包，0选择传感器及相应目标的校准路径。
void acquisition_init(uint8_t fixed_source);
// 传入当前毫秒时间；函数可有有界阻塞等待，应在主循环而非中断中调用。
void acquisition_poll(uint32_t now_ms);
#endif
