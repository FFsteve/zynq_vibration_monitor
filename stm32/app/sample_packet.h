#ifndef SAMPLE_PACKET_H
#define SAMPLE_PACKET_H
#include <stdint.h>
// 编码一组三轴原始值；成功返回 1，空指针返回 0。
int sample_packet_encode(uint8_t seq, const int16_t axes[3], uint8_t out[10]);
#endif
