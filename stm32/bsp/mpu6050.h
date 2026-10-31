#ifndef MPU6050_H
#define MPU6050_H
#include <stdint.h>
int mpu6050_init(uint8_t *who_am_i);
// 返回 -1 表示通信失败，0 表示尚无新样本，1 表示取得一组新样本。
int mpu6050_poll(int16_t axes[3]);
#endif
