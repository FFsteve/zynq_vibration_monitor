// 纯编码函数：将SEQ和三轴signed16写成10字节，不访问外设、不分配动态内存。
// 固定格式为A5 5A SEQ XH XL YH YL ZH ZL CHK，与PL滑动窗口解析器逐字节一致。
// 先转uint16_t取得相同16位补码的无符号表示，再移位拆高/低字节，避免对负数移位的实现差异。
// 大端描述的是轴字段高字节先发；UART硬件在每个字节内部仍按低位先发送，两者不矛盾。
// 校验仅异或下标2到8，包头不参与；调用方至少提供3个轴与10字节输出空间。

#include "sample_packet.h"
#include <stddef.h>
int sample_packet_encode(uint8_t seq, const int16_t axes[3], uint8_t out[10])
{
    unsigned i;
    uint16_t value;
    // 返回0仅表示输入指针无效；输出数组容量由调用方保证，本接口没有长度参数。
    if (axes == NULL || out == NULL) return 0;
    out[0]=0xA5; out[1]=0x5A; out[2]=seq; out[9]=0;
    for (i=0;i<3;i++) {
        value=(uint16_t)axes[i];
        out[3+2*i]=(uint8_t)(value>>8);
        out[4+2*i]=(uint8_t)value;
    }
    // out[9]先清零再逐字节异或，不沿用上次包校验，确保更改SEQ后本包校验随之变化。
    for (i=2;i<=8;i++) out[9]^=out[i];
    return 1;
}
