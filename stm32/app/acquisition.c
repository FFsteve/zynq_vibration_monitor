#include "acquisition.h"
#include "sample_packet.h"
#include "mpu6050.h"
#include "bsp_usart1.h"
#include "bsp_time.h"
#ifndef APP_ACCEL_CALIBRATION
#define APP_ACCEL_CALIBRATION 0
#endif
#if APP_ACCEL_CALIBRATION
#include "accel_calibration.h"
#endif
volatile acquisition_diagnostics g_acquisition;
static uint32_t next_due,last_poll,last_sample;
static uint8_t have_poll,have_sample;
void acquisition_init(uint8_t fixed_source)
{
    unsigned i;
#if APP_ACCEL_CALIBRATION
    accel_calibration_reset();
#endif
    g_acquisition.samples=0;g_acquisition.tx_packets=0;g_acquisition.tx_errors=0;
    g_acquisition.sensor_errors=0;g_acquisition.init_attempts=0;g_acquisition.late_samples=0;
    g_acquisition.who_am_i=0;g_acquisition.online=0;g_acquisition.next_seq=0;
    g_acquisition.fixed_source=(fixed_source!=0);
    for (i=0;i<3;i++) g_acquisition.last_axes[i]=0;
    next_due=bsp_millis();last_poll=0;last_sample=0;have_poll=0;have_sample=0;
}
void acquisition_poll(uint32_t now_ms)
{
    int result;
    int16_t axes[3];
    uint8_t packet[10],id=0;
    unsigned i;
    if (have_poll && now_ms==last_poll) return;
    have_poll=1;last_poll=now_ms;
    if (g_acquisition.fixed_source) {
        if ((int32_t)(now_ms-next_due)<0) return;
        // 延迟后只发一组，不以集中补发制造虚假的均匀采样。
        next_due=now_ms+4;
        axes[0]=1;axes[1]=-1;axes[2]=-32768;
    } else {
        if (!g_acquisition.online) {
            if ((int32_t)(now_ms-next_due)<0) return;
            g_acquisition.init_attempts++;
            result=mpu6050_init(&id);g_acquisition.who_am_i=id;
            g_acquisition.online=(result!=0);next_due=bsp_millis()+1000U;
            if (!result) g_acquisition.sensor_errors++;
            return;
        }
        result=mpu6050_poll(axes);
        if (result<0) {
            g_acquisition.sensor_errors++;g_acquisition.online=0;
            next_due=bsp_millis()+1000U;return;
        }
        if (result==0) return;
#if APP_ACCEL_CALIBRATION
        // 仅对真实传感器样本校正；固定测试包始终保持原约定。
        accel_calibration_process(axes);
#endif
    }
    if (have_sample && (uint32_t)(now_ms-last_sample)>6U) g_acquisition.late_samples++;
    have_sample=1;last_sample=now_ms;
    for (i=0;i<3;i++) g_acquisition.last_axes[i]=axes[i];
    g_acquisition.samples++;
    (void)sample_packet_encode(g_acquisition.next_seq,axes,packet);
    // 获取样本后就递增；发送失败时下次包会留下可见序号缺口。
    g_acquisition.next_seq++;
    if (bsp_usart1_send(packet,10)) g_acquisition.tx_packets++;
    else g_acquisition.tx_errors++;
}
