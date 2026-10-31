#include "stm32f10x.h"
#include "bsp_usart1.h"
#include "bsp_time.h"
#include "board_pinmap.h"
void bsp_usart1_init(void)
{
    GPIO_InitTypeDef gpio;
    USART_InitTypeDef usart;
    RCC_APB2PeriphClockCmd(BOARD_DATA_TX_GPIO_CLOCK|BOARD_DATA_USART_CLOCK,ENABLE);
    GPIO_StructInit(&gpio);gpio.GPIO_Pin=BOARD_DATA_TX_PIN;
    gpio.GPIO_Mode=GPIO_Mode_AF_PP;gpio.GPIO_Speed=GPIO_Speed_50MHz;
    GPIO_Init(BOARD_DATA_TX_GPIO,&gpio);
    USART_StructInit(&usart);usart.USART_BaudRate=115200;
    usart.USART_Mode=USART_Mode_Tx;
    USART_Init(BOARD_DATA_USART,&usart);USART_Cmd(BOARD_DATA_USART,ENABLE);
}
int bsp_usart1_send(const uint8_t *data, unsigned length)
{
    unsigned i;
    uint32_t start=bsp_millis();
    if (data==0 || length==0) return 0;
    // 整次发送共享 10 ms 截止时间；禁止混入调试文本。
    for (i=0;i<length;i++) {
        while (USART_GetFlagStatus(BOARD_DATA_USART,USART_FLAG_TXE)==RESET)
            if ((uint32_t)(bsp_millis()-start)>=10U) return 0;
        USART_SendData(BOARD_DATA_USART,data[i]);
    }
    while (USART_GetFlagStatus(BOARD_DATA_USART,USART_FLAG_TC)==RESET)
        if ((uint32_t)(bsp_millis()-start)>=10U) return 0;
    return 1;
}
