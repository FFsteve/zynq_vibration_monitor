#include "sample_packet.h"
#include <stddef.h>
int sample_packet_encode(uint8_t seq, const int16_t axes[3], uint8_t out[10])
{
    unsigned i;
    uint16_t value;
    if (axes == NULL || out == NULL) return 0;
    out[0]=0xA5; out[1]=0x5A; out[2]=seq; out[9]=0;
    for (i=0;i<3;i++) {
        value=(uint16_t)axes[i];
        out[3+2*i]=(uint8_t)(value>>8);
        out[4+2*i]=(uint8_t)value;
    }
    for (i=2;i<=8;i++) out[9]^=out[i];
    return 1;
}
