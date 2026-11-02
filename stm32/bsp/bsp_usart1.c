// 串口发送驱动：标准库配置USART1为115200、8N1、仅发送；引脚由board_pinmap.h统一指定。
// 当前数据量约每4ms一个10字节包，单包约0.87ms，因此选用简单有界阻塞发送而不引入DMA/中断队列。
// TXE表示发送数据寄存器可写，不表示最后一位已经离开引脚；TC才表示整个末字节发送完成。
// 每次send共享10ms截止，避免每字节重新计时让整包最长等待随长度无限放大。
// 返回0可能已有前缀字节发出；上层不重发同一SEQ，FPGA靠超时/滑动窗口恢复到后续合法包。
// 数据流只允许协议二进制包，调试信息看诊断变量，不能向同一串口混入printf。

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
    // 不启用RX也不把接收引脚配置为输出；此端只承担采集源，FPGA回传由独立测点记录。
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
        // 仅在TXE为1后写下一个字节，否则会覆盖尚未转移到移位寄存器的数据。
        while (USART_GetFlagStatus(BOARD_DATA_USART,USART_FLAG_TXE)==RESET)
            if ((uint32_t)(bsp_millis()-start)>=10U) return 0;
        USART_SendData(BOARD_DATA_USART,data[i]);
    }
    // 所有字节写完后还要等TC，成功返回才表示末字节含停止位已实际发完。
    while (USART_GetFlagStatus(BOARD_DATA_USART,USART_FLAG_TC)==RESET)
        if ((uint32_t)(bsp_millis()-start)>=10U) return 0;
    return 1;
}
