// MPU6050业务接口，调用方不需要关心I2C的ADDR/ACK/STOP细节。
// init通过who_am_i返回实际读到的身份，成功返回1；poll成功时输出按X/Y/Z排列的signed16计数。
// poll返回三态以区分“没有新样本”和“读失败”；只有返回1才能使用本次axes作为新数据。
// 本层不校准，保留原始值以便传感器配置检查与独立校准对照。

#ifndef MPU6050_H
#define MPU6050_H
#include <stdint.h>
int mpu6050_init(uint8_t *who_am_i);
// 返回 -1 表示通信失败，0 表示尚无新样本，1 表示取得一组新样本。
int mpu6050_poll(int16_t axes[3]);
#endif
