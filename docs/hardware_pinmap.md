# Hardware pinmap and traceability — inspect schematic pages before wiring

## Sensor -> STM32
MPU6050 3V3 -> STM32 3.3V; GND -> GND; SDA -> PB7 (I2C1 SDA); SCL -> PB6 (I2C1 SCL); AD0 may remain open on this *specific module* because it has a 4.7k pull-down to GND. Its SDA and SCL have 2.2k pullups to 3.3V. INT unused in V1. Consult `mpu6050_module_schematic.pdf` p1 and `mpu6050_module_manual.pdf` p5.

## STM32 -> PL -> USB UART
- STM32 PA9 / USART1 TX -> baseboard J3 pin 1 / UART2_RX net -> core B35_L20_P -> XC7Z010 package K14 -> `pl_rx`.
- PL `pl_tx` -> XC7Z010 package M15 / B35_L23_N -> J3 pin 2 / UART2_TX net -> USB UART RXD.
- STM32 GND and USB UART GND -> J3 GND (identify 1-pin marking and meter-check before wiring). Do not connect RS-232 DB9 or adapter 5V outputs directly to FPGA IO.
- The baseboard UART2 signals also route to RS232/RS485 circuitry via P1. Inspect the physical jumper setting and remove the relevant link before driving the TTL input externally. Sources: `zynq_baseboard_v3_9.pdf` pp1,5 and `zynq_core_2v5.pdf` p3.

## PL clock and bank voltage
- Core-board X1 is a nominal 50MHz PL oscillator, labeled PL_GCLK -> Bank34 B34_L3_P -> package U13 (core schematic p3). Treat this as a clock **candidate** until matched to the actual core-board revision and Vivado constraints.
- Bank35 schematic power p7 shows +3.3V via an installed-choice 0-ohm path and an alternate VCCIO path marked NC. Confirm board assembly/voltage before asserting LVCMOS33 or wiring.
- Use `constr/top_candidate.xdc` only after checking the actual board and selected FPGA part/package. It is a *candidate*, not a verified/implemented constraint set.
