# 基于 Zynq-7010 的三轴振动监测与声报警

比赛初级组的纯 PL 原型。MPU6050 经 STM32F103C8T6 采集、六面校准并发送三轴包，FPGA 完成 UART 接收、恢复解析、去直流、63 抽头 FIR、窗口 MS/RMS/峰值、滞回报警与有源蜂鸣器控制，再将滤波数据通过 UART 回传。未使用 PS、AXI、Linux 或 PYNQ。

当前交付版本：**v1.0-buzzer-20261102**。用户于 2026-11-02 在本对话确认最终上板完成、蜂鸣器正常响应。此前已有真实采集与 ILA 数值对照；此项声音确认由用户报告，未附新增声学记录。当前主要交付对象为 system_buzzer_top，而不是旧通信 top。设计报告按用户安排之后另行完成，本仓库现有阶段设计/验证报告不是最终设计报告。

## 环境与版本

**必须按 Vivado 2020.2 复现本次构建**，包含其 XSim 和器件支持。选择旧版是沿用已经实际通过的工具环境，不声称在 2025.2/2026.1 验证过。

| 项目 | 本次使用 |
|---|---|
| FPGA | xc7z010clg400-1；领航者底板 V3.9、核心板 2v5 |
| FPGA 工具 | Vivado / XSim 2020.2 |
| 另一仿真器 | ModelSim SE-64 2020.4；仅使用 XSim 也可执行各脚本的 xsim 模式 |
| MCU | STM32F103C8T6，Keil MDK / ARM Compiler 5.06 update 7 build 960 |
| MCU 库 | STM32F10x SPL V3.6.2、CMSIS 设备文件 V3.5.1、CoreSupport V1.30；不使用 HAL/CubeMX |
| 主机 | Windows、PowerShell 5.1；Python 3.12、NumPy 2.3.5；在线串口需要 pyserial |
| 可移植 C 自检 | GCC（本机 MSYS2 UCRT64），不代替 Keil 固件编译 |

安装 Python 依赖：`python -m pip install -r host/requirements.txt`。工具安装位置不同，应使用下述参数覆盖默认路径。STM32 第三方库不在公开 Git 中，见 [依赖准备](docs/reproduction.md)；本地最终工程包已经保存当前依赖的原样副本。

## 自定义目录与竞赛推荐结构的对应

为保留已验证脚本的相对路径，使用原有结构，未机械移动为 src/。工程根 README.md 负责项目与复现；**[skill/README.md](skill/README.md) 专门负责技能的适用范围、用法、失效条件与验证效果，两者不同**。

| 实际目录 | 对应推荐目录与用途 |
|---|---|
| rtl/、stm32/app/、stm32/bsp/、stm32/config/、host/ | src/：Verilog、标准库应用和主机参考/采集工具 |
| sim/、stm32/tests/ | sim/：正常、错误、恢复自检及运行入口 |
| constr/、scripts/、build/ | build/：约束、源码构建脚本、运行后产生的输出；build/ 不作为源文件提交 |
| board/ | board/：本次配套 bit/ltx、校准 HEX、资源时序/DRC/CDC 和下载说明 |
| data/reference/、report/evidence/ | data/：系数、参考、选定实测数据与比对结果 |
| skill/ | skill/：全流程技能、FIR 专项、经验清单、校验脚本与案例 |
| docs/、report/、report/ai_records/ | report/：阶段设计、实际验证、用户交互正文和纠错；最终设计报告后续提交 |
| scripts/package_final.py | 生成独立 zynq_vibration_monitor_final/，不依赖原 Vivado 工作区 |

工程包和公开仓库都不需要 vivado_project/、.Xil/ 或旧 xpr。可复现工程由全部自有源码、相对路径脚本及依赖清单定义。大体积原始 ATK 工程/长采样保留在原工作区，工程包收录选定输入、参考和结果；参见 [证据索引](report/current_release.md)。

## 最短复现流程

先看 [完整复现说明](docs/reproduction.md) 和 [接线指南](docs/wiring_guide.md)，核对板卡版本与电平。以下从当前工程根目录执行：

```powershell
python -X utf8 scripts/verify_delivery.py --root .
python -X utf8 -m unittest discover -s host -p "test_*.py" -v
powershell.exe -NoProfile -ExecutionPolicy Bypass -File sim/run_buzzer.ps1 -Simulator xsim -VivadoBin "D:\Xilinx\Vivado\2020.2\bin"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build_buzzer.ps1 -VivadoBin "D:\Xilinx\Vivado\2020.2\bin"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/build_keil.ps1 -Target SensorCalibratedTrial
```

FPGA 重建结果为 build/buzzer_release/debug/system.bit 与同目录 system.ltx；两者必须配对使用。脚本不操作 Hardware Manager、不自动烧录。STM32 重建结果为 build/stm32/SensorCalibratedTrial/vibration_monitor.hex。

已有下载文件见 [board/README.md](board/README.md)：FPGA 用 board/fpga/debug/system.bit 与 system.ltx，STM32 用 board/stm32/vibration_monitor.hex。SensorSource 是未校准源，FixedSource 是诊断固定源，均不能替代最终 SensorCalibratedTrial。JTAG FPGA 配置掉电不保留，STM32 Flash 程序保留。

## 功能合同与数据解释

串口为 115200、8N1，固定十字节：A5 5A SEQ XH XL YH YL ZH ZL CHK，轴字段为大端 signed16，CHK 为 SEQ 与六个轴数据字节的异或（不含包头）。当前滤波回传由 signed18 算术右移 2 位装入原布局，PC 乘 4 恢复尺度，低 2 位不能恢复；内部 RMS 使用完整 18 位。包内没有模式位，采集必须写明 raw/filtered。

标称 250 Hz；128 样本非重叠窗口，2000 置位/1500 解除、连续两窗确认，均为演示参数。FIR 群延迟 31 样本约 124 ms，与三轴计算 193 个 PL 周期约 3.86 μs、特征对齐 218 周期约 4.36 μs 不同。实际采集约 250.5 Hz，存在周期性约 3 ms 短间隔；未宣称理想等间隔或工业故障诊断精度。

蜂鸣器仅在 quality_valid、alarm_valid 和任一轴报警同时成立时响；失效、复位和解除后关闭。[设计说明](docs/buzzer_design.md) 给出独立模块、单寄存器控制和验证边界。

## 验证与当前完成状态

原 18 份 RTL 已有双工具全阶段 42 次运行与 24 项负向拒绝；蜂鸣器新增模块/顶层另有双工具四项自检和新旧 UART/427 位调试快照逐拍对照。校准有独立重复六面验证、全输入范围 C/Python 对照及真实 I2C→校准 UART 对照。真实滤波 4914 个完整回包与定点参考精确一致，ILA 三窗全部 MS/RMS/峰值与同次输入精确相同。静止、运动报警、正常恢复演练已完成，最终蜂鸣器上板由用户确认。

蜂鸣器版真实 Vivado 2020.2 构建：50 MHz，LUT 6625、FF 11521、DSP 6、36Kb BRAM 等效 12；内部建立/保持裕量 7.377/0.020 ns，0 无时钟寄存器/未约束内部端点；保留 8 项 DRC Warning，未宣称零警告或外部异步接口同步签核。完整事实、历史与当前结果分界见 [当前版本记录](report/current_release.md)。

## 开源与后续

自有代码和技能按 [MIT](LICENSE) 开源，第三方材料见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。仓库：https://github.com/FFsteve/zynq_vibration_monitor 。

当前工程包交付与设计报告分开：最终设计报告、参赛视频和报名平台的其他材料之后处理。本次不引入新算法或再次要求整套板测。
