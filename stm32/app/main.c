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
    if (!bsp_time_init()) { for (;;) {} }
    bsp_usart1_init();bsp_i2c_init();
    acquisition_init(APP_FIXED_SOURCE);
    for (;;) { acquisition_poll(bsp_millis());__WFI(); }
}
