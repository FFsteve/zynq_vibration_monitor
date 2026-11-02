// 时间接口以毫秒为单位；bsp_time_init须在其他依赖超时的外设函数前调用，成功返回1。
// bsp_millis是启动后的32位计数，约49.7天回绕；使用差值计算经过时间，不当作绝对日历时间。
// bsp_delay_ms会等待SysTick中断，不能在时基中断或全局长期关中断时调用。

#ifndef BSP_TIME_H
#define BSP_TIME_H
#include <stdint.h>
int bsp_time_init(void);
uint32_t bsp_millis(void);
void bsp_delay_ms(uint32_t delay);
#endif
