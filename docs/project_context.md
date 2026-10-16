# Project brief and context transfer (2026-09-21)

## Hardware and developer
- One student; comfortable with basic Verilog/testbenches, UART/SPI and STM32; new to Zynq PS.
- ALIENTEK Navigator baseboard V3.9, XC7Z010 core board schematic v2V5.
- Wildfire STM32F103C8T6 minimum board; Wildfire MPU6050 six-axis module; USB-to-UART adapter.
- Goal: low-complexity, demonstrable contest work with quantitative FIR/resource comparisons, not industrial fault-diagnosis claims.

## Agreed initial architecture
MPU6050 (I2C) -> STM32 (sensor acquisition and framing only) -> PL UART RX -> packet parser -> data register -> PL UART TX -> USB UART -> PC. Add FPGA DC/bias removal, fixed-point FIR, windowed mean-square/peak and threshold alarm *after* link validation. FFT is optional. No PS required for V1.

## First milestone and stop criteria
1. Read WHO_AM_I and 6 raw acceleration bytes on STM32; verify sensor orientation, signed data and data-ready timing.
2. Send framed 3-axis samples via USART1 TX PA9, nominal 115200 8N1.
3. Simulate PL UART RX and packet parser including invalid header, checksum error, truncated frame, negative values and resync.
4. Validate board UART RX with an actual signal; return an ACK first, then full framed data.
5. Capture raw logs and test evidence before moving to FIR.

## Draft sensor setup (not yet measured)
MPU6050 address 0x68 (7-bit, AD0 low), PWR_MGMT_1(0x6B)=0x01, CONFIG(0x1A)=0x02, SMPLRT_DIV(0x19)=0x03, ACCEL_CONFIG(0x1C)=0x00. Target 250 samples/s, +/-2g, six raw acceleration bytes from 0x3B..0x40. Confirm timing with measurements: delay_ms(4) is not a synchronization guarantee. The module has its own 3.3V I2C pullups.

## Draft UART input packet — must freeze before RTL
10 bytes: A5 5A SEQ XH XL YH YL ZH ZL CHK, all three axes signed 16-bit, big-endian. CHK=SEQ XOR XH XOR XL XOR YH XOR YL XOR ZH XOR ZL. Frame-valid is asserted for one PL clock after complete verified packet. Define timeout and resynchronization. This is a proposed protocol, not a measured board result.

## Important limitations
MPU6050 frequency/bandwidth and motion tests limit claims. For RMS of vibration remove mean/gravity contribution rather than blindly using 1g. Do not treat UART bandwidth calculation as confirmed real-world sampling quality. No full Vivado/XDC tool run, sensor read or board measurements have been performed by this handoff.
