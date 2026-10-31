# FPGA 正式引脚与时序约束

日期：2026-10-28。用户要求现在完成 FPGA 引脚约束，补充领航者规格书 V1.2 和同板呼吸灯 XDC 截图，并说明实板连接与原理图一致。本次以该声明、项目中的核心板/底板原理图和现有 Vivado 器件设置为依据完成约束；没有进行电压测量、接线或烧录。

## 当前正式配置

器件为 `xc7z010clg400-1`，与现有 `vivado_project/zynq_vibration_monitor.xpr` 一致。规格书 PDF 第 9、14 页列出 Zynq-7010 型号 XC7Z010CLG400-1；第 17 页给出独立 PL 50 MHz 时钟。项目使用 RTL 顶层 `top`，只有以下三个物理端口：

| 顶层端口 | 方向 | PACKAGE_PIN | Bank | IO 标准 | 连接 |
|---|---|---|---|---|---|
| clk | 输入 | U18 | 34 | LVCMOS33 | 核心板 X1 / PL_GCLK，50 MHz |
| pl_rx | 输入 | K14 | 35 | LVCMOS33 | STM32 TX → 底板 J3.1 / UART2_RX |
| pl_tx | 输出 | M15 | 35 | LVCMOS33 | UART2_TX / 底板 J3.2 → 外置 USB 串口 RXD |

正式文件为 `constr/top.xdc`，由原 `top_candidate.xdc` 迁移而来。现有 Vivado 工程只保留新的正式文件引用，不同时加载旧候选约束。`constr/uart_rx_cdc.xdc` 单独用于实现阶段。

## 图纸和示例核对

- 核心板 `docs/hardware/zynq_core_2v5.pdf` 第 3 页：50 MHz X1 经 R7（33 欧姆）到 PL_GCLK/U18；K14=B35_L20_P；M15=B35_L23_N。第 12 页追踪至 X3.56 和 X3.58。
- 底板 `docs/hardware/zynq_baseboard_v3_9.pdf` 第 5 页：J2.56/UART2_RX、J2.58/UART2_TX 分别到 J3.1/J3.2；第 1 页可见 P1 将 UART2 与 RS232/RS485 电路相连。接外部 TTL 信号前按既有接线说明隔离冲突驱动；没有自动改变任何跳帽。
- 核心板第 7、10 页：Bank34/VCCIO 图面额定 3.3V；Bank35 按图示 0R/NC 装配连接 3.3V。新规格书 PDF 第 12、13 页也支持这些 PL Bank 的 3.3V 设计。Vivado 认可该封装的三个引脚和 LVCMOS33 组合；软件检查不测量真实电压。
- 用户截图：sys_clk→U18 与图纸一致，但当前 RTL 端口名为 `clk`，因此使用 `[get_ports clk]`。20.000 ns 对应 50 MHz，时钟名采用 `pl_clk_50m`。
- 截图 N16：核心板第 3 页 N16=B35_L21_N；底板第 5 页映射到 J2.59/PL_RESET，第 1 页显示按键与上拉，规格书第 27 页也显示 PL_RESET 使用 B35_L21_N。该引脚是底板 PL 按键，不是核心板 PS_POR_B 复位。
- 截图 J16：核心板第 3 页 J16 网络为 PL_LED；核心板第 2 页给出该灯电路，规格书第 18 页区分核心板 PL_LED 和 DONE 指示灯。不能将 J16 混同为底板 PL_LED0/1。

当前 `top` 使用内部上电复位，没有 `sys_rst_n`、`led` 或 `sys_clk` 端口，所以没有照搬示例的 N16/J16，也没有重命名已通过仿真的 RTL 端口。要使用按键复位或状态 LED，后续需先设计其顶层功能并配套测试，再添加对应端口约束。

规格书原文件保留在用户路径：

```text
G:/嵌入式/正点原子领航者(V2)ZYNQ开发板资料盘(A盘)/3_开发板原理图和硬件相关文件/硬件相关文件/开发板规格书/【正点原子】领航者ZYNQ开发板规格书V1.2.pdf
```

原 PDF 未复制进公开仓库。文字提取和相关页渲染放在被忽略的 `build/fpga_constraints_review/`。原文件中的教程或下载建议仅作背景，没有被当作额外操作授权。

## UART2 和板载 USB 的区别

本项目保持既有 UART2 的 K14/M15 方案，通过底板扩展接口连接 STM32 和外置 USB 串口。新规格书 PDF 第 28 页的板载 USB 桥通过 P5 接 UART1（PS）或 UART3（PL），不是当前 UART2。

因此，完成本次约束后直接插板载 USB 口，并不意味着能在那个 COM 口看到 M15 的回传。不在未改接线方案和约束的情况下，自动把 pl_tx 换到另一个通道。本轮既有数据通路与 UART 输入协议保持不变。

## 时序约束与异步路径

`top.xdc` 创建周期 20.000 ns 的单一 PL 时钟，指定三个引脚及 IO 标准。它不创建派生波特率时钟；UART 内部计数器均仍使用 50 MHz 主时钟。

UART 发送/接收双方没有共享的同步采样时钟，不虚构外部 input_delay/output_delay 数值：

1. 接收输入仅将 `pl_rx → u_core/u_rx/rx_meta_reg/D` 标为 false path，位于综合后读取的 `uart_rx_cdc.xdc`。
2. 第一级 Q→第二级 D 仍受 50 MHz 时序约束，检查脚本显式要求该路径存在。
3. 输出只对 `pl_tx` 端口设置 false path，不豁免 TX 内部逻辑。串口位周期与采样容差由既有 UART 自检及未来板测验证。

CDC 约束依赖当前层次。如果日后重命名 `u_core/u_rx` 或同步寄存器，必须更新约束并重新检查。不能通过把整个同步链标 false path 来规避对象错误。

## Vivado 工程中的使用

已直接更新本地 `vivado_project/zynq_vibration_monitor.xpr` 的约束文件列表：

| 文件 | 综合 | 实现 |
|---|---|---|
| constr/top.xdc | 使用 | 使用 |
| constr/uart_rx_cdc.xdc | 不使用 | 使用 |

其它顶层、仿真顶层和硬件下载设置未主动调整。本次验证没有打开该工程，而是在独立 build 中运行，避免改动原有工程缓存。若 Vivado 图形界面已经打开该工程，请关闭并重新打开以读取更新的文件列表；不要另加旧候选文件或呼吸灯示例 XDC。

重新建立工程时，把七个 RTL 模块加入 Design Sources，设置设计顶层 `top`，加入这两个 XDC，并取消 CDC 文件的 Used In Synthesis。保留 Used In Implementation。TB 只放 Simulation Sources，不作为板级设计顶层。

## 实际工具检查

在仓库根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_fpga_constraints.ps1
```

默认使用 `D:\Xilinx\Vivado\2020.2\bin`；可通过 `-VivadoBin` 指定其它目录。脚本在 `build/fpga_constraints_check/` 创建内存工程，运行综合、优化、布局、布线、IO/时钟/时序/DRC/CDC 报告，检查结果新鲜度、端口映射、同步链和时序。不会生成比特流或连接硬件。

2026-10-28 15:50:57，Vivado 2020.2 实际完成当前默认整包回传配置：

| 检查 | 实际结果 |
|---|---|
| 器件和端口 | xc7z010clg400-1，三个端口与表中引脚/Bank/IO 标准一致 |
| 综合 | 0 错误、0 严重警告、0 警告 |
| 布局布线 | 完成，设计状态 Fully Routed |
| 50 MHz 建立时序 | WNS=12.708 ns，TNS=0，失败端点=0 |
| 保持时序 | WHS=0.037 ns，THS=0，失败端点=0 |
| 脉宽 | 最差裕量 8.750 ns，失败端点=0 |
| 内部时序覆盖 | 无时钟寄存器=0，未约束内部端点=0 |
| CDC | CDC-3 Info：一条带 ASYNC_REG 的两级单比特同步链 |
| DRC | 0 Error、0 Critical Warning；保留 1 条 ZPS7-1 Warning |
| 资源 | 251 LUT、314 FF、0 BRAM、0 DSP；当前顶层未使用的诊断计数器可被优化 |

`check_timing` 中 no_input_delay=1、no_output_delay=1 均明确归类为已有 false path 的异步 UART 端口；没有将其伪装为共享时钟接口，也不据此证明外部信号品质。

DRC 的 **ZPS7-1：PS7 block required** 提示缺少 PS7 单元以启用正确默认配置。本项目仍按用户要求仅 PL，本轮没有加入 PS7、没有关闭该检查或降低严重度。约束与当前 PL 内部时序检查完成，但这不代表已经消除所有板级/比特流配置问题；后续生成比特流及上板前需评估该项，不能把结果描述为“DRC 零警告”。

本次只验证默认 ACK_ONLY=0、QUEUE_DEPTH=4、50 MHz/115200 配置，没有把其它参数配置当成同样已实现。RTL 完全未改，未重复运行原 ModelSim/XSim 行为自检；它们的既有证据与本轮实现检查相互补充。

## 日志与纠错

主要产物：

```text
build/fpga_constraints_check/constraints_result.txt
build/fpga_constraints_check/vivado.log
build/fpga_constraints_check/io.rpt
build/fpga_constraints_check/clocks.rpt
build/fpga_constraints_check/timing_summary.rpt
build/fpga_constraints_check/drc.rpt
build/fpga_constraints_check/cdc.rpt
build/fpga_constraints_check/exceptions.rpt
build/fpga_constraints_check/rx_sync_timing.rpt
build/fpga_constraints_check/utilization.rpt
build/fpga_constraints_check/routed_top.dcp
```

第一次验证中，XDC 内用于对象数量检查的 if/unset 不属于 Vivado 2020.2 支持的 XDC 命令；同时 Tcl 对 ASYNC_REG 布尔值使用了字符串 TRUE 比较。已经把检查移入独立 Tcl、使用布尔判断，保持 XDC 为受支持的约束命令。首次失败不计为通过；修正后全流程重新运行，最终退出码为 0。

源 PDF 与七个 RTL 文件的 SHA256 在本轮前后均一致；只有本地 XPR 约束引用按上述内容改变。本轮没有复制旧工程生成目录、没有更改下载器/启动模式，也没有写入板卡。

最终静态检查：XPR XML 可解析，器件与两个 XDC 引用及实现专用标记正确；新增文本 UTF-8/行末空白检查通过，PowerShell 语法和 UTF-8 BOM 检查通过，git diff --check 通过。同步链一级至二级的建立裕量报告为 19.272 ns，证明该内部路径没有被例外隐藏。

## 本轮文件清单

- `constr/top_candidate.xdc` 迁移为 `constr/top.xdc`，补齐当前端口、时钟和异步串行输出约束。
- 新增 `constr/uart_rx_cdc.xdc`，仅用于综合后的输入同步例外。
- 新增 `scripts/check_fpga_constraints.ps1`、`scripts/check_fpga_constraints.tcl`，提供独立实现与检查入口。
- 修改本地 `vivado_project/zynq_vibration_monitor.xpr` 的约束列表；该目录按既有规则不纳入 Git，约束与脚本则保留在源码目录。
- 新增本说明，并更新 README、hardware_pinmap、project_context、next_task、阶段一/三测试指南、第三阶段历史报告与 AI 日志，区分历史仿真、当前实现结果与未进行的板测。
