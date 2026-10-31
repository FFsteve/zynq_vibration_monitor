#ifndef STM32F10X_CONF_H
#define STM32F10X_CONF_H
#include "stm32f10x_rcc.h"
#include "stm32f10x_gpio.h"
#include "stm32f10x_i2c.h"
#include "stm32f10x_usart.h"
#include "misc.h"
// 编译检查不启用标准库参数断言；应用自身保留运行时错误与超时出口。
#define assert_param(expr) ((void)0)
#endif
