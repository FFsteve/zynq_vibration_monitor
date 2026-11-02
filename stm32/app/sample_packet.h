// 线缆协议的单一编码入口，固定10字节布局，禁止往同一UART流插入printf文本。
// 本函数只负责序列化，不决定是否校准、何时采样或如何处理发送失败。
// axes可来自原始或校准路径，单位仍是有符号加速度计数；模式由构建目标与采集说明确定。

#ifndef SAMPLE_PACKET_H
#define SAMPLE_PACKET_H
#include <stdint.h>
// 编码一组三轴原始值；成功返回 1，空指针返回 0。
int sample_packet_encode(uint8_t seq, const int16_t axes[3], uint8_t out[10]);
#endif
