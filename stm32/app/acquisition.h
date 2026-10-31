#ifndef ACQUISITION_H
#define ACQUISITION_H
#include <stdint.h>
typedef struct {
    uint32_t samples,tx_packets,tx_errors,sensor_errors,init_attempts,late_samples;
    uint8_t who_am_i,online,fixed_source,next_seq;
    int16_t last_axes[3];
} acquisition_diagnostics;
extern volatile acquisition_diagnostics g_acquisition;
void acquisition_init(uint8_t fixed_source);
void acquisition_poll(uint32_t now_ms);
#endif
