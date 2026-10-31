#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "sample_packet.h"
#include "acquisition.h"
#include "mpu6050.h"
#include "bsp_i2c.h"
#include "bsp_time.h"
#include "bsp_usart1.h"

// 模拟的是应用依赖，不是 STM32 寄存器或真实 I2C 电气行为。
static uint32_t now;
static uint8_t registers[256],tx_log[512][10];
static int bus_ok=1,tx_ok=1,ready=0,mismatch=-1;
static unsigned attempts,burst_reads;
uint32_t bsp_millis(void){return now;}
void bsp_delay_ms(uint32_t delay){now+=delay;}
void bsp_i2c_init(void){}
void bsp_usart1_init(void){}
int bsp_usart1_send(const uint8_t *data,unsigned length)
{
    assert(length==10 && attempts<512);
    memcpy(tx_log[attempts++],data,10);
    return tx_ok;
}
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
    static const uint8_t raw[6]={0,1,0xFF,0xFF,0x80,0};
    unsigned i;
    assert(address==0x68 && data!=0);
    if(!bus_ok)return 0;
    if(reg==0x3A){assert(length==1);*data=(uint8_t)ready;return 1;}
    if(reg==0x3B){assert(length==6);memcpy(data,raw,6);burst_reads++;return 1;}
    for(i=0;i<length;i++)data[i]=registers[reg+i];
    if(reg==mismatch)*data^=1;
    return 1;
}
static void clear_mock(void)
{
    now=0;bus_ok=1;tx_ok=1;ready=0;mismatch=-1;attempts=0;burst_reads=0;
    memset(registers,0,sizeof(registers));registers[0x75]=0x68;
}
static void poll_at(uint32_t time){now=time;acquisition_poll(now);}
int main(int argc,char **argv)
{
    int32_t value;
    int16_t axes[3]={1,-1,-32768};
    uint8_t packet[10],id=0;
    unsigned i;
    FILE *out;
    static const uint8_t golden[10]={0xA5,0x5A,1,0,1,0xFF,0xFF,0x80,0,0x80};
    assert(sample_packet_encode(1,axes,packet));assert(memcmp(packet,golden,10)==0);
    assert(!sample_packet_encode(0,0,packet));assert(!sample_packet_encode(0,axes,0));
    // 覆盖所有 16 位补码数值；不仅测试几个典型正负值。
    for(value=-32768;value<=32767;value++){
        uint16_t expected=(uint16_t)value;uint8_t chk=0;
        axes[0]=(int16_t)value;
        assert(sample_packet_encode((uint8_t)value,axes,packet));
        assert(packet[3]==(uint8_t)(expected>>8)&&packet[4]==(uint8_t)expected);
        for(i=2;i<10;i++)chk^=packet[i];
        assert(chk==0);
    }
    clear_mock();assert(mpu6050_init(&id)&&id==0x68);
    assert(registers[0x19]==3&&registers[0x1A]==2&&registers[0x1C]==0&&registers[0x38]==1);
    assert(mpu6050_poll(axes)==0&&burst_reads==0);
    ready=1;assert(mpu6050_poll(axes)==1&&burst_reads==1);
    assert(axes[0]==1&&axes[1]==-1&&axes[2]==-32768);
    bus_ok=0;assert(mpu6050_poll(axes)==-1);
    clear_mock();registers[0x75]=0x69;assert(!mpu6050_init(&id)&&id==0x69);
    clear_mock();mismatch=0x19;assert(!mpu6050_init(&id));

    clear_mock();acquisition_init(1);
    poll_at(0);poll_at(0);poll_at(1);poll_at(3);assert(attempts==1);
    poll_at(4);assert(attempts==2&&tx_log[1][2]==1&&tx_log[1][9]==0x80);
    tx_ok=0;poll_at(8);assert(g_acquisition.tx_errors==1&&g_acquisition.next_seq==3);
    tx_ok=1;poll_at(12);assert(tx_log[3][2]==3&&g_acquisition.tx_packets==3);
    poll_at(100);assert(attempts==5&&g_acquisition.late_samples==1);
    clear_mock();now=0xFFFFFFFEU;acquisition_init(1);poll_at(now);poll_at(1);poll_at(2);
    assert(attempts==2);

    clear_mock();acquisition_init(0);poll_at(0);
    assert(g_acquisition.online&&g_acquisition.who_am_i==0x68);
    poll_at(200);assert(g_acquisition.samples==0);
    ready=1;poll_at(201);assert(g_acquisition.samples==1&&g_acquisition.last_axes[2]==-32768);
    bus_ok=0;poll_at(202);assert(!g_acquisition.online&&g_acquisition.sensor_errors==1);
    bus_ok=1;poll_at(1201);assert(g_acquisition.init_attempts==1);
    poll_at(1202);assert(g_acquisition.online&&g_acquisition.init_attempts==2);
    ready=1;poll_at(1403);assert(g_acquisition.samples==2&&tx_log[1][2]==1);

    // 将实际 C 编码结果交给独立 Python 解码器作交叉验收。
    if(argc>1){out=fopen(argv[1],"wb");assert(out!=0);
        for(i=0;i<32;i++){
            axes[0]=(int16_t)((int)i-16);axes[1]=(int16_t)(32767-i);axes[2]=(int16_t)(-32768+(int)i);
            assert(sample_packet_encode((uint8_t)i,axes,packet));assert(fwrite(packet,1,10,out)==10);
        }assert(fclose(out)==0);
    }
    puts("PASS firmware_portable values=65536 vectors=32 errors=0");
    return 0;
}
