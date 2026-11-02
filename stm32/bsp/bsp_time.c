// 统一毫秒时基：根据CMSIS提供的SystemCoreClock配置1kHz SysTick，供调度、延时和超时使用。
// SysTick_Handler只递增计数，不在中断里采样/发送，保持中断短小并避免外设等待反过来依赖自身。
// milliseconds为volatile，防止编译器把主循环反复读取优化成一次；无符号32位计数自然回绕。
// 延时使用当前值减起点的无符号差，不直接比较绝对终点，可跨回绕处理正常短延时。
// __WFI仅等待中断节约空转，精度仍受1ms刻度和中断延迟限制，不用于产生精密传感器采样时钟。

#include "stm32f10x.h"
#include "bsp_time.h"
static volatile uint32_t milliseconds;
int bsp_time_init(void)
{
    // 先更新核心频率变量再算重装值；该调用不会重新配置PLL，也不能证明实物时钟频率完全准确。
    SystemCoreClockUpdate();
    milliseconds=0;
    // CMSIS返回0才成功，所以向上转换为布尔成功；失败由main停止启动。
    return SysTick_Config(SystemCoreClock/1000U)==0;
}
void SysTick_Handler(void) { milliseconds++; }
uint32_t bsp_millis(void) { return milliseconds; }
void bsp_delay_ms(uint32_t delay)
{
    uint32_t start=bsp_millis();
    while ((uint32_t)(bsp_millis()-start)<delay) { __WFI(); }
}
