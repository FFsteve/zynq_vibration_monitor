// 采集调度层：把固定测试源或真实MPU6050样本统一转换为同一十字节数据包。
// 本文件维护“离线初始化/在线轮询”两种运行状态，不在外设驱动中混入协议或校准逻辑。
// 固定源按毫秒截止时间约4ms产生一包；真实源每个新毫秒查一次DATA_RDY，不盲目delay_ms(4)后重复读。
// 真实采样并非严格等间隔，未使用FIFO；在线时取最新可用样本，落后造成的历史样本无法凭轮询补回。
// 初始化失败或I2C读失败就离线，约1s后再初始化，既能恢复又避免无间隔反复打总线。
// 校准宏只作用于真实样本，固定1/-1/-32768诊断包永远不改，保证此前通信验收仍有同一参考。
// SEQ在获得样本后递增，发送失败不回退，便于FPGA/PC发现缺口；8位自然回绕。
// g_acquisition供调试器观察计数和最近数值，不是线缆协议，也不是中断与主循环间的消息队列。

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
// next_due用于固定源周期和离线重试；last_poll去重本毫秒，last_sample只诊断过长样本间隔。
static uint32_t next_due,last_poll,last_sample;
static uint8_t have_poll,have_sample;
// 初始化所有运行状态与统计，重置SEQ；在最终目标中同时清校准诊断，保证启动后的统计有共同起点。
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
    // 同一毫秒重复调用会直接退出，避免空转时多次消费同一次数据就绪状态。
    if (have_poll && now_ms==last_poll) return;
    have_poll=1;last_poll=now_ms;
    if (g_acquisition.fixed_source) {
        // 用时间差的符号判断截止而不是直接比较绝对时刻，可跨32位毫秒回绕；调度跨度必须远小于半个计数范围。
        if ((int32_t)(now_ms-next_due)<0) return;
        // 延迟后只发一组，不以集中补发制造虚假的均匀采样。
        next_due=now_ms+4;
        axes[0]=1;axes[1]=-1;axes[2]=-32768;
    } else {
        // 离线状态先校验器件身份、配置并回读；成功后下次poll再读样本，不把初始化成功误当成已采到数据。
        if (!g_acquisition.online) {
            if ((int32_t)(now_ms-next_due)<0) return;
            g_acquisition.init_attempts++;
            result=mpu6050_init(&id);g_acquisition.who_am_i=id;
            g_acquisition.online=(result!=0);next_due=bsp_millis()+1000U;
            if (!result) g_acquisition.sensor_errors++;
            return;
        }
        // 三态返回：负数为通信故障、0为尚无新样本、正数才允许校准/组包；错误时禁止重复发送旧axes。
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
    // 6ms是调度诊断门限，不是传感器采样设置；只统计明显迟到，不强行补发或更改测量值。
    if (have_sample && (uint32_t)(now_ms-last_sample)>6U) g_acquisition.late_samples++;
    have_sample=1;last_sample=now_ms;
    for (i=0;i<3;i++) g_acquisition.last_axes[i]=axes[i];
    g_acquisition.samples++;
    // axes与packet均为本地非空数组，编码入口的空指针保护在此不会失败；完整编码后再一次交给发送层。
    (void)sample_packet_encode(g_acquisition.next_seq,axes,packet);
    // 获取样本后就递增；发送失败时下次包会留下可见序号缺口。
    g_acquisition.next_seq++;
    if (bsp_usart1_send(packet,10)) g_acquisition.tx_packets++;
    else g_acquisition.tx_errors++;
}
