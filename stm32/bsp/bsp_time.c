#include "stm32f10x.h"
#include "bsp_time.h"
static volatile uint32_t milliseconds;
int bsp_time_init(void)
{
    SystemCoreClockUpdate();
    milliseconds=0;
    return SysTick_Config(SystemCoreClock/1000U)==0;
}
void SysTick_Handler(void) { milliseconds++; }
uint32_t bsp_millis(void) { return milliseconds; }
void bsp_delay_ms(uint32_t delay)
{
    uint32_t start=bsp_millis();
    while ((uint32_t)(bsp_millis()-start)<delay) { __WFI(); }
}
