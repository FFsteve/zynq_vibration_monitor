#ifndef BSP_I2C_H
#define BSP_I2C_H
#include <stdint.h>
void bsp_i2c_init(void);
int bsp_i2c_write_reg(uint8_t address, uint8_t reg, uint8_t value);
int bsp_i2c_read(uint8_t address, uint8_t reg, uint8_t *data, unsigned length);
#endif
