// 同步硬件I2C接口，address为未左移的7位地址，reg是器件内部寄存器地址。
// write_reg/read成功返回1，通信或超时失败返回0；read要求非空缓冲且length至少为1。
// 失败时缓冲可能已写入部分字节，调用者必须整组丢弃，不能把半份新数据拼到上次结果中。
// 调用前先初始化毫秒时基与本外设；接口不保证总耗时仅5ms，每个阶段分别有等待上限。

#ifndef BSP_I2C_H
#define BSP_I2C_H
#include <stdint.h>
void bsp_i2c_init(void);
int bsp_i2c_write_reg(uint8_t address, uint8_t reg, uint8_t value);
int bsp_i2c_read(uint8_t address, uint8_t reg, uint8_t *data, unsigned length);
#endif
