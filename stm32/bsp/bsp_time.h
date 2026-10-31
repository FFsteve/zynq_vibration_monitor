#ifndef BSP_TIME_H
#define BSP_TIME_H
#include <stdint.h>
int bsp_time_init(void);
uint32_t bsp_millis(void);
void bsp_delay_ms(uint32_t delay);
#endif
