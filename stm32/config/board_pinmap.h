#ifndef BOARD_PINMAP_H
#define BOARD_PINMAP_H

#include "stm32f10x.h"

// 野火小智双 USB 核心板 + 扩展板；图纸依据和接线见 docs/hardware_pinmap.md。
// MPU6050 使用通讯接口 2：J3/J4 的 3 脚 SCL、4 脚 SDA。
// PB6/PB7 留给扩展板 OLED 总线，本应用不初始化它们。
#define BOARD_MPU_I2C                  I2C2
#define BOARD_MPU_I2C_CLOCK            RCC_APB1Periph_I2C2
#define BOARD_MPU_GPIO                GPIOB
#define BOARD_MPU_GPIO_CLOCK          RCC_APB2Periph_GPIOB
#define BOARD_MPU_SCL_PIN             GPIO_Pin_10
#define BOARD_MPU_SDA_PIN             GPIO_Pin_11

// 通讯接口 3：J9/J10 的 3 脚为 PA9；仅发送，PA10 不配置为输出。
#define BOARD_DATA_USART              USART1
#define BOARD_DATA_USART_CLOCK        RCC_APB2Periph_USART1
#define BOARD_DATA_TX_GPIO            GPIOA
#define BOARD_DATA_TX_GPIO_CLOCK      RCC_APB2Periph_GPIOA
#define BOARD_DATA_TX_PIN             GPIO_Pin_9

#endif
