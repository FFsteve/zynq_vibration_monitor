// 器件驱动层：核对身份、写入并回读配置，随后以轮询数据就绪的方式读取XYZ加速度。
// 当前使用7位地址0x68，WHO_AM_I必须为0x68；不把能ACK简单等同于正确器件。
// 配置意图：0x6B唤醒并选时钟，0x1A设DLPF，0x19设分频，0x1C选±2g，0x38允许DATA_RDY状态。
// 名义配置约250Hz、16384计数/g；实际样本间隔受轮询与传感器影响，应以已保存实测记录为准。
// 每次先读INT_STATUS(0x3A)，有新样本才从0x3B连续读6字节，避免把三个独立读取时刻拼成一组三轴。
// 只读取加速度，不读取陀螺仪/温度，也未启用FIFO；读状态清除后到取数仍可能有调度延迟。
// 错误只向上返回，不在本层发送错误文本或重复旧样本；重初始化由acquisition负责。

#include "mpu6050.h"
#include "bsp_i2c.h"
#include "bsp_time.h"
#define MPU_ADDRESS 0x68
// 高低字节合成无符号16位，再显式减65536解释负数，避免依赖超范围无符号转有符号的实现行为。
static int16_t signed_word(uint8_t high, uint8_t low)
{
    int32_t value=(int32_t)(((uint16_t)high<<8)|low);
    if (value>=32768) value-=65536;
    return (int16_t)value;
}
int mpu6050_init(uint8_t *who_am_i)
{
    // 配置表按写入顺序排列；与后面的回读使用同一表，防止配置值与验收期望分散不一致。
    static const uint8_t config[][2]={{0x6B,0x01},{0x1A,0x02},{0x19,0x03},{0x1C,0x00},{0x38,0x01}};
    uint8_t id=0,value;
    unsigned i;
    if (who_am_i==0) return 0;
    if (!bsp_i2c_read(MPU_ADDRESS,0x75,&id,1)) return 0;
    *who_am_i=id;
    if (id!=0x68) return 0;
    // 先软件复位再等待内部恢复；复位后才配置各项，不能省略等待就立即依赖旧寄存器状态。
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
    // 尚未就绪不是故障，返回0让主循环稍后再问；不能将它计为总线失败。
    if (!(status&1)) return 0;
    if (!bsp_i2c_read(MPU_ADDRESS,0x3B,raw,6)) return -1;
    for (i=0;i<3;i++) axes[i]=signed_word(raw[2*i],raw[2*i+1]);
    return 1;
}
