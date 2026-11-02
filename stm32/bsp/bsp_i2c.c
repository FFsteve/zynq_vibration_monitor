// 硬件I2C驱动层：使用STM32F10x标准外设库，提供寄存器写入和连续字节读取，不含MPU6050业务逻辑。
// 引脚/外设集中由board_pinmap.h选择；GPIO使用复用开漏，SCL/SDA依赖总线已有上拉。
// 每次状态等待都有约5ms时基上限，遇到NACK/总线错误/仲裁丢失/溢出即退出，不无限卡在while。
// 读寄存器先以发送方向写寄存器地址，再重复START切接收方向，保持同一笔寻址读取事务。
// STM32F1接收尾部的ADDR、ACK、POS与STOP顺序敏感，1字节、2字节、至少3字节必须分开处理。
// 仅在关键寄存器相邻操作处短暂关中断，并恢复原PRIMASK；不能屏蔽整个等待，否则SysTick超时停走。
// recover重置外设并返回失败，让采集层离线重试；不主动翻转GPIO产生解锁脉冲，也不承诺修复持续短路。
// 本驱动同步、有界阻塞，要求调用时SysTick可运行，不能从禁止时基中断的上下文调用。

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
    // 清外设旧状态再配置标准模式100kHz；I2C_StructInit保留7位地址等默认选项。
    I2C_DeInit(BOARD_MPU_I2C);I2C_StructInit(&i2c);
    i2c.I2C_ClockSpeed=100000;i2c.I2C_Ack=I2C_Ack_Enable;
    I2C_Init(BOARD_MPU_I2C,&i2c);I2C_Cmd(BOARD_MPU_I2C,ENABLE);
}
// 这是轮询等待的统一出口；用无符号差值计算经过时间，跨毫秒计数回绕仍可工作。
static int wait_flag(uint32_t flag, FlagStatus status)
{
    uint32_t start=bsp_millis();
    for (;;) {
        if (BOARD_MPU_I2C->SR1 & (I2C_SR1_AF|I2C_SR1_BERR|I2C_SR1_ARLO|I2C_SR1_OVR)) return 0;
        if (I2C_GetFlagStatus(BOARD_MPU_I2C,flag)==status) return 1;
        if ((uint32_t)(bsp_millis()-start)>=5U) return 0;
    }
}
// F1通过按顺序读SR1、SR2清ADDR；volatile保证两次硬件读取不被编译器优化掉。
static void clear_address(void)
{
    volatile uint32_t dummy;
    dummy=BOARD_MPU_I2C->SR1;dummy=BOARD_MPU_I2C->SR2;(void)dummy;
}
static int address_phase(uint8_t address, uint8_t direction)
{
    I2C_GenerateSTART(BOARD_MPU_I2C,ENABLE);
    if (!wait_flag(I2C_FLAG_SB,SET)) return 0;
    // 上层传7位地址0x68；标准库接口需要左移后的地址字段，读写方向由direction补上，不能重复左移。
    I2C_Send7bitAddress(BOARD_MPU_I2C,(uint8_t)(address<<1),direction);
    return wait_flag(I2C_FLAG_ADDR,SET);
}
// 等待硬件清STOP位后恢复ACK/POS默认状态，避免前一笔短读的NACK设置污染下一笔读。
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
// 发送顺序为START、写地址、寄存器地址、寄存器值、STOP；BTF保证上一字节已完成传输再推进。
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
    // 双字节接收提前选择POS=Next，NACK才落在正确字节；其他长度使用Current。
    I2C_NACKPositionConfig(BOARD_MPU_I2C,length==2?I2C_NACKPosition_Next:I2C_NACKPosition_Current);
    if (!address_phase(address,I2C_Direction_Receiver)) return recover();
    // 按 AN2824 区分单字节、双字节和多字节结尾；轮询期间不屏蔽时基中断。
    // 单字节必须在清ADDR前关ACK，并紧跟STOP；若先放行接收再处理，可能错误接纳多余字节。
    if (length==1) {
        I2C_AcknowledgeConfig(BOARD_MPU_I2C,DISABLE);
        mask=__get_PRIMASK();__disable_irq();
        clear_address();I2C_GenerateSTOP(BOARD_MPU_I2C,ENABLE);__set_PRIMASK(mask);
        if (!wait_flag(I2C_FLAG_RXNE,SET)) return recover();
        data[0]=I2C_ReceiveData(BOARD_MPU_I2C);
    // 双字节在清ADDR后关ACK，等BTF表示两字节就位，再发STOP并读出；关键顺序不可与普通循环合并。
    } else if (length==2) {
        mask=__get_PRIMASK();__disable_irq();
        clear_address();I2C_AcknowledgeConfig(BOARD_MPU_I2C,DISABLE);__set_PRIMASK(mask);
        if (!wait_flag(I2C_FLAG_BTF,SET)) return recover();
        mask=__get_PRIMASK();__disable_irq();
        I2C_GenerateSTOP(BOARD_MPU_I2C,ENABLE);data[0]=I2C_ReceiveData(BOARD_MPU_I2C);__set_PRIMASK(mask);
        data[1]=I2C_ReceiveData(BOARD_MPU_I2C);
    } else {
        clear_address();
        // 多字节先读到仅剩3字节；BTF意味着数据寄存器与移位寄存器均已有数据，给尾部收口留出确定条件。
        while (remaining>3) {
            if (!wait_flag(I2C_FLAG_BTF,SET)) return recover();
            data[index++]=I2C_ReceiveData(BOARD_MPU_I2C);remaining--;
        }
        if (!wait_flag(I2C_FLAG_BTF,SET)) return recover();
        mask=__get_PRIMASK();__disable_irq();
        // 剩3字节时先NACK并读倒数第三字节，之后再等BTF、STOP并读最后两字节，避免尾部多ACK一字节。
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
