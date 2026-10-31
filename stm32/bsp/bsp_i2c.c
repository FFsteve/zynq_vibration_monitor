#include "stm32f10x.h"
#include "bsp_i2c.h"
#include "bsp_time.h"
#include "board_pinmap.h"

// 使用板级头文件选择硬件 I2C2，保持原有有界轮询与错误恢复流程。
void bsp_i2c_init(void)
{
    GPIO_InitTypeDef gpio;
    I2C_InitTypeDef i2c;
    RCC_APB2PeriphClockCmd(BOARD_MPU_GPIO_CLOCK,ENABLE);
    RCC_APB1PeriphClockCmd(BOARD_MPU_I2C_CLOCK,ENABLE);
    GPIO_StructInit(&gpio);gpio.GPIO_Pin=BOARD_MPU_SCL_PIN|BOARD_MPU_SDA_PIN;
    gpio.GPIO_Mode=GPIO_Mode_AF_OD;gpio.GPIO_Speed=GPIO_Speed_50MHz;
    GPIO_Init(BOARD_MPU_GPIO,&gpio);
    I2C_DeInit(BOARD_MPU_I2C);I2C_StructInit(&i2c);
    i2c.I2C_ClockSpeed=100000;i2c.I2C_Ack=I2C_Ack_Enable;
    I2C_Init(BOARD_MPU_I2C,&i2c);I2C_Cmd(BOARD_MPU_I2C,ENABLE);
}
static int wait_flag(uint32_t flag, FlagStatus status)
{
    uint32_t start=bsp_millis();
    for (;;) {
        if (BOARD_MPU_I2C->SR1 & (I2C_SR1_AF|I2C_SR1_BERR|I2C_SR1_ARLO|I2C_SR1_OVR)) return 0;
        if (I2C_GetFlagStatus(BOARD_MPU_I2C,flag)==status) return 1;
        if ((uint32_t)(bsp_millis()-start)>=5U) return 0;
    }
}
static void clear_address(void)
{
    volatile uint32_t dummy;
    dummy=BOARD_MPU_I2C->SR1;dummy=BOARD_MPU_I2C->SR2;(void)dummy;
}
static int address_phase(uint8_t address, uint8_t direction)
{
    I2C_GenerateSTART(BOARD_MPU_I2C,ENABLE);
    if (!wait_flag(I2C_FLAG_SB,SET)) return 0;
    I2C_Send7bitAddress(BOARD_MPU_I2C,(uint8_t)(address<<1),direction);
    return wait_flag(I2C_FLAG_ADDR,SET);
}
static int finish(void)
{
    uint32_t start=bsp_millis();
    while (BOARD_MPU_I2C->CR1 & I2C_CR1_STOP)
        if ((uint32_t)(bsp_millis()-start)>=5U) return 0;
    I2C_NACKPositionConfig(BOARD_MPU_I2C,I2C_NACKPosition_Current);
    I2C_AcknowledgeConfig(BOARD_MPU_I2C,ENABLE);
    return 1;
}
static int recover(void)
{
    // 只恢复外设状态；若线路持续被拉低，后续仍会有界失败，不承诺物理自愈。
    if (BOARD_MPU_I2C->SR2 & I2C_SR2_MSL) I2C_GenerateSTOP(BOARD_MPU_I2C,ENABLE);
    I2C_SoftwareResetCmd(BOARD_MPU_I2C,ENABLE);I2C_SoftwareResetCmd(BOARD_MPU_I2C,DISABLE);
    bsp_i2c_init();
    return 0;
}
int bsp_i2c_write_reg(uint8_t address, uint8_t reg, uint8_t value)
{
    if (address>0x7F || !wait_flag(I2C_FLAG_BUSY,RESET)) return recover();
    if (!address_phase(address,I2C_Direction_Transmitter)) return recover();
    clear_address();
    if (!wait_flag(I2C_FLAG_TXE,SET)) return recover();
    I2C_SendData(BOARD_MPU_I2C,reg);
    if (!wait_flag(I2C_FLAG_BTF,SET)) return recover();
    I2C_SendData(BOARD_MPU_I2C,value);
    if (!wait_flag(I2C_FLAG_BTF,SET)) return recover();
    I2C_GenerateSTOP(BOARD_MPU_I2C,ENABLE);
    if (!finish()) return recover();
    return 1;
}
int bsp_i2c_read(uint8_t address, uint8_t reg, uint8_t *data, unsigned length)
{
    unsigned index=0,remaining=length;
    uint32_t mask;
    if (data==0 || length==0 || address>0x7F) return 0;
    if (!wait_flag(I2C_FLAG_BUSY,RESET)) return recover();
    if (!address_phase(address,I2C_Direction_Transmitter)) return recover();
    clear_address();
    if (!wait_flag(I2C_FLAG_TXE,SET)) return recover();
    I2C_SendData(BOARD_MPU_I2C,reg);
    if (!wait_flag(I2C_FLAG_BTF,SET)) return recover();
    I2C_AcknowledgeConfig(BOARD_MPU_I2C,ENABLE);
    I2C_NACKPositionConfig(BOARD_MPU_I2C,length==2?I2C_NACKPosition_Next:I2C_NACKPosition_Current);
    if (!address_phase(address,I2C_Direction_Receiver)) return recover();
    // 按 AN2824 区分单字节、双字节和多字节结尾；轮询期间不屏蔽时基中断。
    if (length==1) {
        I2C_AcknowledgeConfig(BOARD_MPU_I2C,DISABLE);
        mask=__get_PRIMASK();__disable_irq();
        clear_address();I2C_GenerateSTOP(BOARD_MPU_I2C,ENABLE);__set_PRIMASK(mask);
        if (!wait_flag(I2C_FLAG_RXNE,SET)) return recover();
        data[0]=I2C_ReceiveData(BOARD_MPU_I2C);
    } else if (length==2) {
        mask=__get_PRIMASK();__disable_irq();
        clear_address();I2C_AcknowledgeConfig(BOARD_MPU_I2C,DISABLE);__set_PRIMASK(mask);
        if (!wait_flag(I2C_FLAG_BTF,SET)) return recover();
        mask=__get_PRIMASK();__disable_irq();
        I2C_GenerateSTOP(BOARD_MPU_I2C,ENABLE);data[0]=I2C_ReceiveData(BOARD_MPU_I2C);__set_PRIMASK(mask);
        data[1]=I2C_ReceiveData(BOARD_MPU_I2C);
    } else {
        clear_address();
        while (remaining>3) {
            if (!wait_flag(I2C_FLAG_BTF,SET)) return recover();
            data[index++]=I2C_ReceiveData(BOARD_MPU_I2C);remaining--;
        }
        if (!wait_flag(I2C_FLAG_BTF,SET)) return recover();
        mask=__get_PRIMASK();__disable_irq();
        I2C_AcknowledgeConfig(BOARD_MPU_I2C,DISABLE);data[index++]=I2C_ReceiveData(BOARD_MPU_I2C);__set_PRIMASK(mask);
        if (!wait_flag(I2C_FLAG_BTF,SET)) return recover();
        mask=__get_PRIMASK();__disable_irq();
        I2C_GenerateSTOP(BOARD_MPU_I2C,ENABLE);data[index++]=I2C_ReceiveData(BOARD_MPU_I2C);__set_PRIMASK(mask);
        if (!wait_flag(I2C_FLAG_RXNE,SET)) return recover();
        data[index]=I2C_ReceiveData(BOARD_MPU_I2C);
    }
    if (!finish()) return recover();
    return 1;
}
