// 校准主机自检入口：在模拟外设下运行真实校准和采集，确认校准目标的集成行为。
// 既检查原地与分离缓冲等价，也检查诊断、饱和、错误恢复、固定测试源旁路及SEQ缺口。
// 全遍历65536种输入，每个输入分别作用于XYZ各自参数，共196608个轴值，输出供独立Python参考核查。
// 每条输出含10字节协议包加1字节饱和掩码；这是测试文件格式，不是新增UART协议字段。
// 此测试验证整数实现与目标路径，不是对新物理传感器重新进行六面采集或机械标定。

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "accel_calibration.h"
#include "acquisition.h"
#include "sample_packet.h"
#include "bsp_i2c.h"
#include "bsp_time.h"
#include "bsp_usart1.h"
// 模拟外设依赖，只检查应用调用，不冒充真实I2C/采样周期测试。
static uint32_t now;
static uint8_t registers[256],last_packet[10];
static int bus_ok=1,ready=0,tx_ok=1;
static unsigned sent;
static const int16_t sensor_raw[3]={16964,513,6382};
uint32_t bsp_millis(void){return now;}
void bsp_delay_ms(uint32_t delay){now+=delay;}
void bsp_i2c_init(void){}
void bsp_usart1_init(void){}
int bsp_i2c_write_reg(uint8_t address,uint8_t reg,uint8_t value)
{
    assert(address==0x68);
    if(!bus_ok)return 0;
    if(reg==0x6B && value==0x80){memset(registers,0,sizeof(registers));registers[0x75]=0x68;}
    else registers[reg]=value;
    return 1;
}
int bsp_i2c_read(uint8_t address,uint8_t reg,uint8_t *data,unsigned length)
{
    unsigned i;
    assert(address==0x68);
    if(!bus_ok)return 0;
    if(reg==0x3A){assert(length==1);*data=(uint8_t)ready;return 1;}
    if(reg==0x3B){
        assert(length==6);
        for(i=0;i<3;i++){
            uint16_t word=(uint16_t)sensor_raw[i];
            data[2*i]=(uint8_t)(word>>8);data[2*i+1]=(uint8_t)word;
        }
        return 1;
    }
    for(i=0;i<length;i++)data[i]=registers[reg+i];
    return 1;
}
int bsp_usart1_send(const uint8_t *data,unsigned length)
{
    assert(length==10);memcpy(last_packet,data,10);sent++;
    return tx_ok;
}
static void poll_at(uint32_t value){now=value;acquisition_poll(now);}
static void clear_mock(void)
{
    now=0;bus_ok=1;ready=0;tx_ok=1;sent=0;
    memset(registers,0,sizeof(registers));registers[0x75]=0x68;
}
int main(int argc,char **argv)
{
    int32_t value;
    unsigned i;
    uint8_t mask,packet[10],expected_packet[10];
    int16_t axes[3],expected[3],alias[3];
    FILE *out;
    assert(argc==2);
    assert(accel_calibration_apply(0,expected)==0x80);
    assert(accel_calibration_apply(sensor_raw,0)==0x80);
    mask=accel_calibration_apply(sensor_raw,expected);assert(mask==0);
    memcpy(alias,sensor_raw,sizeof(alias));
    accel_calibration_apply(alias,alias);assert(memcmp(alias,expected,sizeof(alias))==0);
    // 集成检查必须通过真实acquisition路径，证明宏启用后校准发生在组包前，而不只是单函数算对。
    clear_mock();acquisition_init(0);poll_at(0);assert(g_acquisition.online);
    poll_at(201);assert(sent==0 && g_accel_calibration.samples==0);
    ready=1;poll_at(202);assert(sent==1 && g_accel_calibration.samples==1);
    assert(sample_packet_encode(0,expected,expected_packet));
    assert(memcmp(last_packet,expected_packet,10)==0);
    for(i=0;i<3;i++){
        assert(g_accel_calibration.last_raw[i]==sensor_raw[i]);
        assert(g_accel_calibration.last_corrected[i]==expected[i]);
        assert(g_acquisition.last_axes[i]==expected[i]);
    }
    bus_ok=0;poll_at(203);assert(!g_acquisition.online && g_accel_calibration.samples==1);
    bus_ok=1;poll_at(1202);assert(g_acquisition.init_attempts==1);
    poll_at(1203);assert(g_acquisition.online && g_acquisition.init_attempts==2);
    poll_at(1404);assert(last_packet[2]==1 && g_accel_calibration.samples==2);
    tx_ok=0;poll_at(1408);assert(g_acquisition.tx_errors==1 && g_acquisition.next_seq==3);
    tx_ok=1;poll_at(1412);assert(last_packet[2]==3);
    // 即使编译启用校准，固定源仍必须逐字节等于历史诊断包，避免失去通信基线。
    clear_mock();acquisition_init(1);poll_at(0);
    axes[0]=1;axes[1]=-1;axes[2]=-32768;
    assert(sample_packet_encode(0,axes,expected_packet));
    assert(memcmp(last_packet,expected_packet,10)==0 && g_accel_calibration.samples==0);
    axes[0]=-32768;axes[1]=-32768;axes[2]=-32768;
    accel_calibration_process(axes);assert(g_accel_calibration.clipped_samples==1);
    assert(g_accel_calibration.last_clipped_axes!=0);
    accel_calibration_reset();assert(g_accel_calibration.samples==0 && g_accel_calibration.clipped_samples==0);
    // 全部有符号16位输入交给独立Python参考核查，包括舍入和饱和边界。
    out=fopen(argv[1],"wb");assert(out!=0);
    for(value=-32768;value<=32767;value++){
        axes[0]=(int16_t)value;axes[1]=(int16_t)value;axes[2]=(int16_t)value;
        mask=accel_calibration_apply(axes,axes);
        assert(sample_packet_encode((uint8_t)value,axes,packet));
        assert(fwrite(packet,1,10,out)==10 && fwrite(&mask,1,1,out)==1);
    }
    assert(fclose(out)==0);
    puts("PASS calibration_c values_per_axis=65536 axes=3 integration_errors_recovery_fixed_bypass=passed");
    return 0;
}
