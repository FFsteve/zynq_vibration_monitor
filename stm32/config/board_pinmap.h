// 板级适配集中入口：把I2C实例、时钟门控、GPIO端口和引脚放在同一处，避免驱动内散落硬编码。
// 更换板卡时应成组核对并修改这些宏，同时重读实际原理图；不能只改I2C2为I2C1却沿用旧引脚/时钟。
// 本文件描述已选接口，不控制供电跳帽，也不能由宏定义推断实际插线、电平或通电状态。
// 原理图核查与接线边界记录在docs/hardware_pinmap.md和docs/stm32_board_review.md。

#ifndef BOARD_PINMAP_H
#define BOARD_PINMAP_H

#include "stm32f10x.h"

// 野火小智双 USB 核心板 + 扩展板；图纸依据和接线见 docs/hardware_pinmap.md。
// MPU6050 使用通讯接口 2：J3/J4 的 3 脚 SCL、4 脚 SDA。
// PB6/PB7 留给扩展板 OLED 总线，本应用不初始化它们。
// I2C外设在APB1，相关GPIO在APB2，两个时钟都必须使能后才能配置对应寄存器。
#define BOARD_MPU_I2C                  I2C2
#define BOARD_MPU_I2C_CLOCK            RCC_APB1Periph_I2C2
#define BOARD_MPU_GPIO                GPIOB
#define BOARD_MPU_GPIO_CLOCK          RCC_APB2Periph_GPIOB
#define BOARD_MPU_SCL_PIN             GPIO_Pin_10
#define BOARD_MPU_SDA_PIN             GPIO_Pin_11

// 通讯接口 3：J9/J10 的 3 脚为 PA9；仅发送，PA10 不配置为输出。
// USART1及其GPIO均由APB2门控；只选择TX用途，接收/下载设置仍由既有工程与实物连接决定。
#define BOARD_DATA_USART              USART1
#define BOARD_DATA_USART_CLOCK        RCC_APB2Periph_USART1
#define BOARD_DATA_TX_GPIO            GPIOA
#define BOARD_DATA_TX_GPIO_CLOCK      RCC_APB2Periph_GPIOA
#define BOARD_DATA_TX_PIN             GPIO_Pin_9

#endif
