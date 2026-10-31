# 第二阶段测试指南

本阶段只进行仿真。用户暂缓上板，不需要接线、开发 PS、启动 Hardware Manager 或生成比特流。

## 一键运行

在 PowerShell 中执行以下命令，使用仅对本次新进程生效的执行策略，避免此前的脚本启动限制：

```powershell
Set-Location D:\Code\zynq_vibration_monitor
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage2.ps1 -Simulator both
```

也可只运行一套仿真器或一项测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage2.ps1 -Simulator modelsim
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage2.ps1 -Simulator xsim
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage2.ps1 -Simulator both -Test packet_parser
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage2.ps1 -Simulator both -Test uart_tx
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage2.ps1 -Simulator both -Test uart_packet_link
```

默认工具路径仍是 `D:/modelsim/win64` 和 `D:/Xilinx/Vivado/2020.2/bin`，可以用 `-ModelSimBin`、`-VivadoBin` 指定其他安装目录。未更改系统或用户的永久执行策略。

脚本在运行前将该项结果作废为 NOT_RUN，并检查工具退出码、TB 的完成标志、错误数和新结果文件。任何一项失败就退出，不继续把后续结果当作全部通过。第一阶段脚本和 TB 保持原样。

## 测试项目与通过标准

| 测试名与顶层 | 检查内容 | 本次通过标记 |
|---|---|---|
| packet_parser / tb_packet_parser | 全包原子更新、正负极值、大端、载荷含包头、连续输入、损坏/插入/删除/截断后的恢复、超时边界、UART 错误优先级、序号、复位 | PASS packet_parser checks=171 errors=0 |
| uart_tx / tb_uart_tx | 全部 256 字节、每位完整时长、低位先发、完整停止位、连续握手、忙时输入变化、请求短脉冲、复位终止与恢复、两组分频 | PASS uart_tx checks=2931922 errors=0 |
| uart_packet_link / tb_uart_packet_link | TX→RX→解析器仿真链路；负数、序号回绕、坏校验、实际 2 ms 超时、BREAK、复位后恢复 | PASS uart_packet_link checks=14 errors=0 |

`checks` 是各 TB 自己累计的检查步数，不是不同模块之间可比较的覆盖率。实际失败数必须为 0。故意注入的 checksum、timeout、UART 错误事件不代表自检失败。

解析器单元测试将超时缩短为 32 拍，以逐拍检查 LIMIT-1、LIMIT、LIMIT+1；链路测试使用默认 100000 拍，验证 50 MHz 下真实 2 ms 超时。TX 同时测试每位 434 拍和 33 拍。

每个仿真器产生自己的目录：

```text
build/modelsim_stage2/packet_parser/
build/modelsim_stage2/uart_tx/
build/modelsim_stage2/uart_packet_link/
build/xsim_stage2/packet_parser/
build/xsim_stage2/uart_tx/
build/xsim_stage2/uart_packet_link/
```

各目录保存 `<测试名>_result.txt`。ModelSim 保存 transcript.log 和 vsim.wlf；XSim 保存 xvlog.log、xelab.log、xsim.log 和对应 wdb。编译产物全部位于已忽略的 build 中。

## ModelSim 图形界面

以解析器为例，在 Transcript 中执行以下 Tcl。若目录中已经有 work，跳过 vlib：

```tcl
file mkdir D:/Code/zynq_vibration_monitor/build/modelsim_stage2/packet_parser
cd D:/Code/zynq_vibration_monitor/build/modelsim_stage2/packet_parser
vlib work
vmap work D:/Code/zynq_vibration_monitor/build/modelsim_stage2/packet_parser/work
vlog -work work D:/Code/zynq_vibration_monitor/rtl/packet_parser.v D:/Code/zynq_vibration_monitor/sim/tb/tb_packet_parser.v
vsim -onfinish stop -voptargs=+acc work.tb_packet_parser
add wave -r /tb_packet_parser/dut/*
run -all
examine -radix unsigned /tb_packet_parser/test_done
examine -radix unsigned /tb_packet_parser/error_count
```

最后两个值应为 1、0，并出现对应 PASS 行。

测试 TX 时添加 `rtl/uart_tx.v` 和 `sim/tb/tb_uart_tx.v`，顶层改为 `tb_uart_tx`，观察 `/tb_uart_tx/main_case/dut/*`。测试模块链路时添加三个 RTL 和 `sim/tb/tb_uart_packet_link.v`，顶层改为 `tb_uart_packet_link`，观察 tx_dut、rx_dut、parser_dut。

自动批处理脚本会退出 ModelSim；图形界面观察请使用上述手动步骤。重跑使用 `restart -f` 后 `run -all`。

## Vivado 图形界面行为仿真

1. 在仿真工程中添加 Design Sources：`rtl/uart_rx.v`、`rtl/uart_tx.v`、`rtl/packet_parser.v`。
2. 添加 Simulation Sources：本阶段三个 `sim/tb/tb_*.v` 文件。
3. 在 Simulation Sources 中，将需要运行的 TB 设为仿真顶层。三个项目分别运行，不使用文件名猜测当前顶层。
4. 运行 Run Simulation → Run Behavioral Simulation，再在仿真控制台执行 `run all`。
5. 检查对应 PASS 行、顶层 test_done=1、error_count=0。
6. 切换另一测试时关闭当前仿真，重新设置仿真顶层并启动。

本轮实际执行的是两套仿真器的命令行行为仿真，未实际操作 GUI。自动入口的 XSim 路线不需要 FPGA part；如果手动建 Vivado 工程，应按实物选择完整 part，不代填未知速度等级。不要给这些 TB 添加板级候选 XDC，时钟、复位和串行激励由 TB 产生。

## 推荐观察的信号

| 模块 | 观察信号 | 正常含义 |
|---|---|---|
| 包解析器 | byte_valid_i、byte_i、fill_count、frame_valid_o、seq_o、x_o/y_o/z_o | 前九字节不更新样本，第十字节成功校验时一次性提交 |
| 包解析器错误 | checksum_error_o、timeout_o、seq_error_o | 候选失败/超时/合法包序号不连续；最后一种与整包有效同拍 |
| TX | valid_i、ready_o、tx_o、busy_o、done_o | 握手后起始位拉低，低位先发，每位 N 拍，10N 拍完成 |
| 仿真链路 | tx_line、rx_data、rx_valid、rx_error、frame_valid | 串行位被还原为字节，再形成完整三轴包 |

坏包时数据保持不变是正常行为，不应把“data 仍是旧值”当成解析失败。TX 忙时仅打一拍 valid 不会排队；需要等待的请求必须保持 valid 与数据直到握手。

下一阶段才会增加顶层、回传控制、PC 工具和 STM32 采集；当前测试链路不是 PC 回显系统。
