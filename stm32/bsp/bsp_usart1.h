#ifndef BSP_USART1_H
#define BSP_USART1_H
#include <stdint.h>
void bsp_usart1_init(void);
int bsp_usart1_send(const uint8_t *data, unsigned length);
#endif
