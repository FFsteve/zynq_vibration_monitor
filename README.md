# Zynq-7010 振动监测项目交接说明

七阶段软件实现、全部自检回归与最终下载构建已完成，候选版为v1.0-rc1。已提供原始/滤波/ILA三种FPGA下载文件、两个STM32固件目标、源码与哈希；新版整体实物验收和传感器校准仍待执行。先看[交付入口](docs/stage7_delivery.md)、[完整上板方案](docs/board_test_plan.md)和[需求核对](report/requirements_audit.md)。修改前阅读 `AGENTS.md`、`docs/project_context.md`、`docs/hardware_pinmap.md`。

项目目标：MPU6050 -> STM32F103C8T6 I2C 采集 -> Zynq-7010 PL UART 接收 -> 数据包解析 -> 去直流/FIR/窗口特征与报警 -> UART 发送 -> PC。第一版不涉及 PS。

下一步见 `docs/next_task.md`。接线或烧录前，核对实物版本、UART 电平和约束。

当前两块开发板应如何连接，见 **[接线指南](docs/wiring_guide.md)**：包含 STM32→FPGA、FPGA→外置 USB 串口，以及 MPU6050 的逐针接线、共地和供电跳帽说明。

使用外部仪器检查当前通信，见 **[DL16 逻辑分析仪测试指南](docs/logic_analyzer_guide.md)**：已按实际购买的 DL16 和 ATK-Logic 手册修订，包含探头连接、软件设置、UART/I2C 解码和故障定位。

四份厂商原始 PDF 位于 `docs/hardware/`，仅供本地参考，默认不纳入 Git。向竞赛要求的公开 GitHub/Gitee 仓库发布 PDF 前，必须核实作者的再分发条款；不允许再分发时，发布来源链接和自行整理的引脚说明。

## 第一阶段：UART 接收器

- RTL：`rtl/uart_rx.v`，默认 50 MHz / 115200，使用前需要同步复位。
- 自检仿真顶层：`sim/tb/tb_uart_rx.v` 中的 `tb_uart_rx`。
- 设计说明：`docs/uart_rx_design.md`。
- ModelSim 和 Vivado 操作：`docs/stage1_test_guide.md`。
- 实际验证证据：`report/stage1_validation.md`。

在仓库根目录的 PowerShell 中执行：

```powershell
.\sim\run_uart_rx.ps1 -Simulator both
```

可用 `-ModelSimBin`、`-VivadoBin` 指定工具安装目录。输出统一写入已忽略的 `build/`。若执行策略阻止脚本运行，按测试指南使用仅本次进程生效的启动方式。

本阶段没有板级顶层或比特流。根据核心板原理图，候选时钟引脚已纠正为 U18；实际板卡版本、电压和跳线仍未验证。

## 文档和注释语言

后续 Markdown 文档和代码说明性注释统一使用中文。文件名、标识符、命令、工具指令和自动解析所需的日志标记保持原样，具体要求见 `AGENTS.md`。

## 第二阶段：包解析与 UART 发送

- RTL：`rtl/packet_parser.v`、`rtl/uart_tx.v`。
- 自检：`sim/tb/tb_packet_parser.v`、`sim/tb/tb_uart_tx.v`、`sim/tb/tb_uart_packet_link.v`。
- 设计与协议：`docs/stage2_design.md`，沿用十字节布局并明确超时和恢复。
- 操作指南：`docs/stage2_test_guide.md`。
- 实际验证：`report/stage2_validation.md`。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage2.ps1 -Simulator both
```

可用 `-Test packet_parser`、`-Test uart_tx` 或 `-Test uart_packet_link` 单独运行。输出位于 `build/modelsim_stage2/` 和 `build/xsim_stage2/`。本阶段链路仅用于仿真，不是板级或 PC 回显系统；第一阶段 RX 文件保持不变。

## 第三阶段：原始数据通信闭环

- FPGA：`power_on_reset`、`return_controller`、`monitor_core`、`top`，每个模块有对应自检。
- PC：`host/` 保存二进制、三轴 CSV 和 JSON；仿真捕获可离线验收，在线串口尚未实测。
- STM32：`stm32/keil/vibration_monitor.uvprojx`，两个目标使用用户提供的标准库，支持固定数据与 MPU6050 采集。
- 设计、操作、证据：`docs/stage3_design.md`、`docs/stage3_test_guide.md`、`report/stage3_validation.md`。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage3.ps1 -Simulator both
python -X utf8 host/check_stage3_captures.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stm32\build_keil.ps1
```

第三阶段初次交付时，ModelSim 与 XSim 四项测试、PC 七项自检均通过，STM32 两个 Keil 目标均为 0 错误、0 警告。库文件保持原样并仅在本地使用；当时未进行 Vivado 综合/实现。后续引脚适配与实现检查见下文；2026-10-29～30用户实物采集的基本闭环证据见 `report/stm32_fixed_uart_validation.md`、`report/sensor_source_validation_20261030.md` 和 `report/sensor_zdown_validation_20261030.md`，不等于全部量值/长期验收完成。

2026-10-28 已按用户提供的双 USB 核心板及扩展板资料适配 STM32：MPU6050 使用通讯接口 2 的 I2C2/PB10/PB11，USART1 TX 保留 PA9；接线针号、3.3V 供电选择及本次重建结果见 `docs/stm32_board_review.md`。

## FPGA 正式约束

2026-10-28 已将候选约束迁移为 `constr/top.xdc`，当前为 clk/U18、pl_rx/K14、pl_tx/M15，50 MHz、LVCMOS33。`constr/uart_rx_cdc.xdc` 只用于实现阶段，本地 Vivado 工程引用已同步更新。详细图纸依据、与呼吸灯示例的区别和工具证据见 `docs/fpga_constraints.md`。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_fpga_constraints.ps1
```

默认配置已经实际综合和布局布线，WNS=12.708 ns、WHS=0.037 ns。DRC 保留一条 ZPS7-1 Warning，不描述为零警告；该检查流程未生成比特流或操作烧录。此后用户提供了外部通信波形，仍只使用 PL。

## 第四阶段：去直流与定点 FIR

已实现 `dc_remove`、`fir_lp_serial`、`vibration_filter`、`filter_monitor_core`，均有自检。ModelSim与XSim四项通过，RTL导出和负向参数检查通过，OOC内部建立/保持裕量9.198ns/0.117ns；接口/父级时钟及板级签核待最终集成，工具警告按报告保留。

- 设计：[接口、格式、状态机和周期](docs/stage4_design.md)。
- 验收：[测试计划](docs/stage4_test_plan.md)。
- 实际结果：[数值验证记录](report/stage4_design_validation.md)。
- 实现结果：[RTL验证记录](report/stage4_validation.md)；操作：[测试指南](docs/stage4_test_guide.md)。
- 数值参考：`host/stage4_reference.py`，需NumPy；系数位于 `data/reference/stage4/`。

```powershell
& 'C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 host/stage4_reference.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage4.ps1 -Simulator both
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_stage4_synthesis.ps1
```

暂按250Hz、5～30Hz通带及50Hz以上阻带设计；三轴独立去直流后作63抽头FIR，内部结果18位。原始UART回传及板级top未改，不会自动把D1变成滤波数据。去直流不代表MPU6050已校准，当前软件验收不等于实物滤波效果通过。

## 第五阶段：窗口特征与报警

已完成三轴128样本非重叠窗口的均方值、整数RMS、绝对峰值，以及每轴2000/1500计数滞回、连续两窗确认。质量不足、丢样或断流会取消窗口，使报警状态无效；阈值仍是演示参数。

ModelSim/XSim四项自检、实际RTL导出对照和八项非法参数检查通过；完整内部核心OOC建立/保持裕量9.063ns/0.088ns。新结果为内部接口，原始十字节回传、板级top和STM32保持原有实现。

- [设计与时序](docs/stage5_design.md)、[自检计划](docs/stage5_test_plan.md)。
- [实际验收记录](report/stage5_validation.md)、[仿真操作指南](docs/stage5_test_guide.md)。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage5.ps1 -Simulator both
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_stage5_synthesis.ps1
```

上板集中最终阶段，传感器校准、真实采样稳定性和阈值标定尚待实物验证。工具警告及OOC边界见验收记录。

## 第六阶段：系统联调与量化

已按用户补充截图恢复原计划，见[分期计划](docs/stage_plan.md)。新增 `system_top` 独立完整链路入口，以 `RETURN_FILTERED=0/1` 选择原始/滤波回传。滤波结果右移2位放入十字节包，PC解码后乘4恢复尺度；内部18位计算和RMS/报警不变，包内没有模式标志，必须记录采集模式。

ModelSim/XSim新模块及队列/解析器回归、实际RTL导出量化通过；两种完整板级实现通过。原始模式建立/保持裕量5.205ns/0.037ns，滤波模式8.300ns/0.028ns，均保留完整计算支路，警告按实际报告记录。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage6.ps1 -Simulator both
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_stage6_implementation.ps1
```

- [第六阶段设计](docs/stage6_design.md)、[操作指南](docs/stage6_test_guide.md)、[实际验收](report/stage6_validation.md)。
- [实物记录模板](report/stage6_board_record.md)：仍未实测，按此前安排最终阶段统一上板。

原 `top` 和原Vivado工程保留为此前通信入口，本阶段成果在独立build目录；没有生成下载文件。第七阶段再完成全量回归、冻结版本、最终重建和干净启动的实物演示。

## 第七阶段：最终回归与候选交付

全部18个RTL模块、19个自检顶层已实际回归；两工具共42项阶段运行及24项负向拒绝通过。PC协议/回放11项、可移植C和两个Keil全量重建通过。原始/滤波/ILA三版从源码重新实现并成功生成bit，调试版有匹配ltx和21组427位探针。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_stage7.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_release.ps1
```

- [最终验收与边界](report/stage7_validation.md)、[需求完整性核对](report/requirements_audit.md)。
- [完整上板方案](docs/board_test_plan.md)、[逐项记录表](report/final_board_record.md)。
- [项目可复用技能](skill/fir-validation/SKILL.md)。
- 本地候选包：`build/release/v1.0-rc1/`；同版冻结后不覆盖，修复另建版本。

原始/滤波/调试版50MHz内部建立裕量分别5.205/8.300/5.432ns，保持裕量0.037/0.028/0.014ns，各保留8项DRC Warning。本轮未操作硬件，不能把生成下载文件写成新增板测通过。首个实物步骤是FixedSource与raw版通信，不先调零偏或改FIR。
