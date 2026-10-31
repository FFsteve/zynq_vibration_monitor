#include "mpu6050.h"
#include "bsp_i2c.h"
#include "bsp_time.h"
#define MPU_ADDRESS 0x68
static int16_t signed_word(uint8_t high, uint8_t low)
{
    int32_t value=(int32_t)(((uint16_t)high<<8)|low);
    if (value>=32768) value-=65536;
    return (int16_t)value;
}
int mpu6050_init(uint8_t *who_am_i)
{
    static const uint8_t config[][2]={{0x6B,0x01},{0x1A,0x02},{0x19,0x03},{0x1C,0x00},{0x38,0x01}};
    uint8_t id=0,value;
    unsigned i;
    if (who_am_i==0) return 0;
    if (!bsp_i2c_read(MPU_ADDRESS,0x75,&id,1)) return 0;
    *who_am_i=id;
    if (id!=0x68) return 0;
    if (!bsp_i2c_write_reg(MPU_ADDRESS,0x6B,0x80)) return 0;
    bsp_delay_ms(100);
    for (i=0;i<sizeof(config)/sizeof(config[0]);i++) {
        if (!bsp_i2c_write_reg(MPU_ADDRESS,config[i][0],config[i][1])) return 0;
        if (config[i][0]==0x6B) bsp_delay_ms(100);
    }
    // 回读关键配置；这只能检测通信/配置不一致，不能证明实际采样品质。
    for (i=0;i<sizeof(config)/sizeof(config[0]);i++) {
        if (!bsp_i2c_read(MPU_ADDRESS,config[i][0],&value,1)||value!=config[i][1]) return 0;
    }
    return 1;
}
int mpu6050_poll(int16_t axes[3])
{
    uint8_t status,raw[6];
    unsigned i;
    if (axes==0) return -1;
    if (!bsp_i2c_read(MPU_ADDRESS,0x3A,&status,1)) return -1;
    if (!(status&1)) return 0;
    if (!bsp_i2c_read(MPU_ADDRESS,0x3B,raw,6)) return -1;
    for (i=0;i<3;i++) axes[i]=signed_word(raw[2*i],raw[2*i+1]);
    return 1;
}
