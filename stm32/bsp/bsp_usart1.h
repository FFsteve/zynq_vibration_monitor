// 单向二进制UART接口；send在主循环调用，成功1、无效参数/超时0，可能部分发送失败。
// 输入缓冲至少包含length字节；阻塞期间仍需保持时基中断可运行，用于10ms超时。
// 返回成功不代表FPGA已解析或PC已收到，链路验收仍需比较实际回传记录。

#ifndef BSP_USART1_H
#define BSP_USART1_H
#include <stdint.h>
void bsp_usart1_init(void);
int bsp_usart1_send(const uint8_t *data, unsigned length);
#endif
