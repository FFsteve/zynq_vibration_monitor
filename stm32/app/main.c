// 程序入口：先建立毫秒时基，再初始化串口、I2C与采集状态，之后反复轮询一次并等待中断。
// 时基必须先可用：后续I2C、UART有界等待和传感器复位延时都依赖bsp_millis推进。
// APP_FIXED_SOURCE由Keil目标宏选择；本文件的默认1只是未指定宏时的诊断固定源回退。
// FixedSource发送固定极值包验证通信；SensorSource读取原始传感器；SensorCalibratedTrial另启用校准宏。
// 最终演示应选择SensorCalibratedTrial，不要通过手改这里的默认宏去混淆多个已验证目标。
// __WFI让CPU等待中断再继续，当前主要由1ms SysTick唤醒；这不是精确4ms硬件触发采样。
// 采样/错误恢复在普通主循环中执行，不放入SysTick中断，避免长I2C事务阻塞时基。

#include "stm32f10x.h"
#include "acquisition.h"
#include "bsp_time.h"
#include "bsp_usart1.h"
#include "bsp_i2c.h"
#ifndef APP_FIXED_SOURCE
#define APP_FIXED_SOURCE 1
#endif
// 原理图确认外部晶振标称 8 MHz；沿用用户 CMSIS 的 72 MHz 配置，尚未实测。
int main(void)
{
    // SysTick配置失败时停止启动，避免进入依赖时基却永远不能超时的外设等待。
    if (!bsp_time_init()) { for (;;) {} }
    bsp_usart1_init();bsp_i2c_init();
    acquisition_init(APP_FIXED_SOURCE);
    // acquisition_poll自身保证同一毫秒只处理一次；若外设耗时跨毫秒，下一轮用当前时间重新判断。
    for (;;) { acquisition_poll(bsp_millis());__WFI(); }
}
