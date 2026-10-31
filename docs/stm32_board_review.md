# STM32 核心板与扩展板引脚核查

日期：2026-10-28，时区 Asia/Shanghai。用户确认使用野火小智 STM32F103C8T6 双 USB 核心板及配套扩展板，要求按五份资料调整程序。本记录区分图纸连接、本轮选定的软件接线方案与尚未进行的实物验证。

## 本次结论与接线

保留 USART1 TX/PA9，将 MPU6050 从 I2C1/PB6/PB7 改到 I2C2/PB10/PB11，使用扩展板通讯接口 2。PB6/PB7 同时连到扩展板 OLED；I2C 可以共享总线，旧选择并非必然有错。本次采用独立 I2C2 是为了使传感器与 OLED 分开，并不是原理图强制只能如此。

| 功能 | 当前程序 | 扩展板位置 | 核心板位置 |
|---|---|---|---|
| MPU6050 SCL | I2C2 / PB10，复用开漏 | 通讯接口 2：J3/J4.3 | J3.4 |
| MPU6050 SDA | I2C2 / PB11，复用开漏 | 通讯接口 2：J3/J4.4 | J3.3 |
| MPU6050 3V3 | 接 VCC4，选择 3.3V | 通讯接口 2：J3/J4.6 | 不由 GPIO 供电 |
| MPU6050 GND | 共地 | 通讯接口 2：J3/J4.5 | GND |
| 发送到 FPGA | USART1 TX / PA9，复用推挽，115200、8N1 | 通讯接口 3：J9/J10.3；也可从 J31.5 引出 | J4.5 |
| 串口接收 | 当前未启用 PA10 | 通讯接口 3：J9/J10.4 | J4.6 |

同名连接器位号在核心板和扩展板中不是同一个物理连接器，表中分列说明。例如核心板 J3 与扩展板 J3 不可混淆。针号以相应原理图为准，接线时核对实物 1 脚/丝印；没有根据 PDF 上的左右排列推断实物朝向。

扩展板 J32 的 2—3 连接选择 VCC4=3.3V，1—2 连接选择 5V。本轮不改变实物跳帽；接模块前仍需核实针号和实际电压。模块按四根独立线连接 3V3/GND/SDA/SCL；INT 不接，AD0 保留模块自身下拉，地址仍为 0x68。本程序不驱动接口其余 PB8/PB9 引脚。

扩展板通讯接口 1 和 2 共享 PB10/PB11、PB8/PB9，只是部分针序不同。这里选择接口 2，不将接口 1 当作另一条独立总线。通讯接口 4 与 OLED 共用 PB6/PB7，本轮不新增 OLED 功能。

## 晶振与 USB 串口核查

核心板原理图 PDF 第 4 页的 Y1 标称 8 MHz，PD0/PD1 连接；引脚表 Sheet1 第 40、41 行一致。Y2 为 32.768 kHz。现有 Keil HSE_VALUE=8000000 与用户 CMSIS 默认 72 MHz 系统配置保持不变；标称与实际运行频率分开，未测波形。

核心板原理图 PDF 第 5 页 J5 将 PA9（.7）与 USB 桥 RXD（.8）、PA10（.9）与 USB 桥 TXD（.10）分别引出，默认跳帽短接；第 6 页可核对桥芯片信号方向。核心板规格书第 12 页和引脚表 Sheet1 第 14、15 行也确认默认连接。

因此，PA9 仍适合本项目的二进制发送，不能把规格书中的“调试串口”解释成必须向该串口混入 printf。本轮也未将 PA10 配置为输出。核心板 USB 桥看到 PA9 的 STM32 原始包，与 FPGA 验证后回传是两条不同观察路径；若未来把同一 USB 桥 RXD 改接 FPGA，应先隔离 PA9 路径，避免连接两个 TX 输出。

资料存在一处文字差异：规格书称桥芯片为 CH340C，原理图 U3 标 CH340X。本次不据此猜测实际芯片型号，只采用两者一致的串口连接信息。保留 PA13/PA14 的 SWD，PA1/PA2/PA3 的 RGB 与 PA11/PA12 的 USB Device 连接均不改动，不变更 BOOT、JTAG/SWD 或下载设置。

## 五份来源与定位

原文件保持在用户指定的 F 盘，没有复制进公开仓库，也没有修改、导出或覆盖原始表格。PDF 页码均为从 1 开始的物理页面编号；扩展板原理图有 5 个 PDF 页面，部分标题栏仍写 Sheet 4 of 4，不能只用标题栏定位。

| 来源 | 定位与用途 |
|---|---|
| 核心板规格书 V1.0.2 | PDF 第 12 页：USB 转串口、PA9/PA10 默认跳帽连接 |
| 核心板原理图 | PDF 第 4 页：MCU 与 8 MHz 晶振；第 5 页：J3/J4、J5；第 6 页：USB 桥与 ISP 连接 |
| 核心板引脚分配表 | Sheet1 第 14/15 行 PA9/PA10，第 27/28 行 I2C1，第 31/32 行 I2C2，第 40/41 行 8 MHz 晶振 |
| 扩展板规格书 V1.0.1 | PDF 第 12 页：通讯接口 1/2/3/4、I2C2 与 OLED 的接口分配说明 |
| 扩展板原理图 | PDF 第 3 页：通讯接口和引脚；第 4 页：OLED/J32/排针 |

用户指定的原始路径：

```text
F:/野火小智STM32F103C8专题资料/1-硬件资料/原理图_尺寸图_规格书_IO表格_封装库/[野火小智]STM32F103C8T6核心板_双USB款_规格书V1.0.2.pdf
F:/野火小智STM32F103C8专题资料/1-硬件资料/原理图_尺寸图_规格书_IO表格_封装库/[野火小智]STM32F103C8核心板_双USB款_原理图.pdf
F:/野火小智STM32F103C8专题资料/1-硬件资料/原理图_尺寸图_规格书_IO表格_封装库/[野火小智]STM32F103C8核心板_双USB款_引脚分配表.xls
F:/野火小智STM32F103C8专题资料/5-配套模块/0-野火小智STM32F103C8T6扩展板/野火小智STM32F103C8T6扩展板_规格书V1.0.1.pdf
F:/野火小智STM32F103C8专题资料/5-配套模块/0-野火小智STM32F103C8T6扩展板/原理图_尺寸图/野火小智STM32F103C8T6扩展板原理图.pdf
```

PDF 通过文字提取及相关页面渲染交叉核对，XLS 使用 xlrd 2.0.2 只读读取；读取依赖仅安装在被忽略的 build/stm32_pin_review/python_deps。抽取文本和页面图像保留在同一 build 目录供本地核查，不修改全局依赖或源资料。原资料中的下载/调试建议没有被当成本次操作授权。

## 程序修改

| 文件 | 修改与作用 |
|---|---|
| stm32/config/board_pinmap.h | 新增集中引脚定义：I2C2、PB10/PB11、USART1/PA9 与相应 RCC 时钟 |
| stm32/bsp/bsp_i2c.c / .h | 从 bsp_i2c1 改名为通用接口；GPIO、APB1 时钟、所有寄存器/收发/错误恢复操作均使用同一个板级 I2C 选择 |
| stm32/bsp/bsp_usart1.c | 保留 PA9/USART1 TX 行为，改用统一板级定义，便于对照接线 |
| stm32/bsp/mpu6050.c | 调用通用 I2C 接口；地址、寄存器、采样与数据包规则不变 |
| stm32/app/main.c | 更新 I2C 初始化函数名及晶振依据注释 |
| stm32/tests/test_portable.c | 更新模拟依赖函数名，继续使用原有行为验收 |
| stm32/keil/vibration_monitor.uvprojx | 两个目标的 I2C 源文件路径均更新，避免继续编译旧驱动 |
| stm32/README.md、docs/hardware_pinmap.md、project_context.md、stage3_design.md | 更新当前接线和已确认/未验证事项 |
| report/stage3_validation.md、ai_devlog.md | 保留历史结果并记录本轮变更与新证据 |

## 实际测试

在 `D:\Code\zynq_vibration_monitor` 执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stm32\test_portable.ps1 -Python 'C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stm32\build_keil.ps1
```

| 检查 | 实际结果 |
|---|---|
| 应用可移植回归 | PASS firmware_portable values=65536 vectors=32 errors=0 |
| C 编码→Python 解码 | PASS firmware_vectors samples=32 errors=0 |
| Keil FixedSource | 2026-10-28 11:34:50 全量重建，0 错误、0 警告；Code=4408、RO=280、RW=60、ZI=1060 |
| Keil SensorSource | 2026-10-28 11:34:52 全量重建，0 错误、0 警告；Code=3856、RO=280、RW=60、ZI=1060 |

编译器为 ARM Compiler 5.06 update 7 build 960，Keil 脚本只重建、不下载。两份依赖文件已确认分别使用 APP_FIXED_SOURCE=1/0、HSE_VALUE=8000000，并包含实际用户库和 board_pinmap.h。回归验证的是应用和组包；标准库 BSP 经过实际编译和图面核查，没有据此声称真实 I2C 时序通过。

收尾检查通过：两个目标的自有源码路径均存在并引用 bsp_i2c.c，旧 bsp_i2c1 标识已从当前应用/驱动/测试中移除；源文件 UTF-8 与行末空白检查、Keil XML 解析、git diff --check 通过。与既有清单比较，88 个厂商库文件无修改；UART RX/TX/解析器源码哈希与第三阶段记录一致。

日志为 `build/stm32/FixedSource/keil_build.log` 和 `build/stm32/SensorSource/keil_build.log`，本轮重建已更新这些构建产物；2026-10-27 的第三阶段结果仍作为历史记录保留在报告中。

FPGA RTL、XDC、PC 协议和十字节布局没有本轮修改，因此未重复运行 ModelSim/XSim。没有接线、测量、上板或下载。本轮完成软件引脚适配，实物装配版本、跳帽、电压和插线方向仍需现场核对。
