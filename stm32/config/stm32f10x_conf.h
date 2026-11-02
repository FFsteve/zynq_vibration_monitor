// 标准外设库的项目级配置入口，仅包含当前所需RCC、GPIO、I2C、USART及中断辅助声明。
// 由USE_STDPERIPH_DRIVER路径使用，不是HAL/CubeMX生成配置；厂商库本体保留原许可与原文件。
// assert_param在本构建关闭，只去除库参数断言；I2C/UART自己的错误检查、超时和采集诊断仍执行。
// 增加外设时应按需引入相应头文件，不能仅加入头文件就认为已完成时钟、引脚和外设初始化。

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
