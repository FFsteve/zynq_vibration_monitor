# 第三阶段 STM32 固件

2026-10-31新增独立实验校准工程 `keil/vibration_calibration.uvprojx`，目标 `SensorCalibratedTrial`。当前六面记录各仅50ms，参数只供验证初值，尚未完成正式标定。原本工程的FixedSource/SensorSource仍按下文工作。实验工程、测试命令、数据含义及结果见 `../report/mpu6050_calibration_analysis_20261031.md`。

应用工程位于 `keil/vibration_monitor.uvprojx`，使用用户提供的 CMSIS 与 STM32F10x 标准外设库。没有 HAL、CubeMX、RTOS 或串口文本打印。库目录只在本地引用，源码未改；再分发授权未核实，已在 Git 中忽略 `Libraries/`。

## 工程目标与软件配置

| 项目 | 当前设置与边界 |
|---|---|
| 器件 | STM32F103C8，中容量启动文件；Flash 64 KiB、SRAM 20 KiB |
| 编译器 | ARM Compiler 5，C99，MicroLIB |
| 时钟 | 核心板原理图 Y1 标称 8 MHz；保留 HSE 8 MHz → 72 MHz，运行频率尚未实测 |
| FixedSource | APP_FIXED_SOURCE=1，每 4 ms 尝试发送 (1,-1,-32768)，SEQ 从 0 递增 |
| SensorSource | APP_FIXED_SOURCE=0，检查 WHO_AM_I，配置 MPU6050，轮询 DATA_RDY 后连续读六字节 |
| 串口 | USART1，仅 TX，PA9，115200、8N1；通讯接口 3 的 J9/J10.3，实际插线未验证 |
| I2C | I2C2，PB10/SCL、PB11/SDA，100 kHz，7 位地址 0x68；通讯接口 2 的 J3/J4.3/.4 |

所用库的版本标记：CMSIS 设备文件 V3.5.1、标准外设驱动 V3.6.2。驱动需要 `core_cm3.c`，不要重复添加其它启动文件、SystemInit 或 SysTick_Handler。2026-10-28 根据用户补充的五份资料，将 MPU6050 从 I2C1 改为 I2C2，为 OLED 保留 PB6/PB7；PA9 保持原配置。引脚统一定义在 `config/board_pinmap.h`，详细图纸依据、针序和供电跳帽见 `../docs/hardware_pinmap.md`、`../docs/stm32_board_review.md`。通讯接口 2 的 VCC4 必须选择 3.3V，不能把它当作固定 3.3V 接口。

## 文件职责

| 文件 | 职责 |
|---|---|
| app/main.c | 初始化时基、串口、I2C，选择数据源，循环调度 |
| app/acquisition.c / .h | 固定源或传感器采集、故障后延迟重试、发包及诊断 |
| app/sample_packet.c / .h | 保持既有十字节、大端、XOR 布局；没有协议变更 |
| bsp/bsp_time.c / .h | SysTick 1 ms、毫秒计时、延时 |
| bsp/bsp_usart1.c / .h | 标准库初始化与有超时的二进制发送 |
| bsp/bsp_i2c.c / .h | 根据板级配置使用 I2C2；有界轮询、重复 START、1/2/多字节 ACK/STOP、错误恢复 |
| bsp/mpu6050.c / .h | 身份与配置回读、DATA_RDY、六字节原始加速度及补码转换 |
| config/stm32f10x_conf.h | 本应用使用的标准库头文件与断言配置 |
| config/board_pinmap.h | 统一选择传感器 I2C 外设、GPIO、时钟和 USART1 TX 引脚 |
| keil/vibration_monitor.uvprojx | 两个目标，共用本地库，产物输出到仓库 build |
| tests/test_portable.c | 模拟应用依赖，测试正常、错误与恢复，并生成 C 编码向量 |
| tests/check_vectors.py | 用独立 PC 解码器验证实际 C 编码结果 |
| test_portable.ps1 / build_keil.ps1 | 可重复的 PC 测试与 Keil 全量编译入口 |

MPU6050 配置沿用既有草案：0x6B=01、0x1A=02、0x19=03、0x1C=00；增加设备复位和 0x38=01，使 DATA_RDY 状态可轮询。未新增 INT 接线。每次成功取得样本后递增序号，即使后续串口发送失败也保留缺口。没有 FIFO，所以不能保证调度迟延时保留全部传感器样本。

`g_acquisition` 可供未来调试观察：who_am_i、online、samples、tx_packets、tx_errors、sensor_errors、init_attempts、late_samples、next_seq 和 last_axes。late_samples 仅提示两次已读样本间隔偏长，不能准确计数传感器丢样；序号也只覆盖已取得的样本。

I2C 每段等待有 5 ms 超时；接收结尾按 [ST AN2824](https://www.st.com/resource/en/application_note/an2824-stm32f10xxx-ic-optimized-examples-stmicroelectronics.pdf) 区分长度处理。短临界区屏蔽中断，等待期间保留 SysTick；故障后重置外设。SDA/SCL 被持续拉低等物理故障仍可能一直失败，本实现不包含 GPIO 时钟脉冲解锁。

## 测试

在仓库根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stm32\test_portable.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stm32\build_keil.ps1
```

操作细节见 `../docs/stage3_test_guide.md`，实际证据见 `../report/stage3_validation.md`。本轮只编译和测试，未下载固件、未验证 I2C 引脚时序、未测实际采样率。
