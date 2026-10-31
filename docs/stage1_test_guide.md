# 第一阶段测试指南：UART RX

工程根目录现在为 `D:/Code/zynq_vibration_monitor`。被测文件为
`rtl/uart_rx.v`，仿真顶层为 `sim/tb/tb_uart_rx.v` 中的 `tb_uart_rx`。
均为 Verilog，无须 PS、IP 或板卡仿真库。生成文件放在已忽略的 `build/`。

## 1. 验收结果与覆盖范围

TB 同时运行两组：main_case 为 50 MHz/115200、每位 434 拍；odd_case 为
50 MHz/1500000、每位 33 拍，用于奇数分频与计数器位宽检查。
每组应接收 699 字节，产生 4 次预期停止位错误事件。完整验收行应为：

```text
PASS tb_uart_rx: bytes=1398 framing=8 errors=0
```

framing=8 是主动注入的坏停止位/BREAK 事件，不是测试失败。errors 必须为 0。
仿真约在 64.3 ms 结束，1000 ns 的默认 Run 时间远远不够。

| 项目 | 自动检查 |
|---|---|
| 复位、空闲 | 输出复位值、无伪字节、无未知输出 |
| 全部字节 | 00..FF 连续发送，仅一个停止位，无额外间隔 |
| 随机数据与间隔 | 128 字节，固定随机种子，可复现 |
| 异步相位 | 20 个起始相位覆盖一个 20 ns PL 周期 |
| 波特率与抖动 | TX baud 偏差 -2%、-1%、+1%、+2%，叠加最高 1% 逐位时长扰动 |
| 假起始与边界 | 中心已高则拒收；越过中心的低脉冲可能被接受 |
| 坏停止位 | 对 00/A5/FF 注入；一次错误脉冲、不提交数据、之后恢复 |
| BREAK | 长低电平只报告一次错误，恢复高电平后继续接收 |
| WAIT_HIGH | 复位时 RX 低；不足一整位的高脉冲不能重新使能 |
| 中途复位 | START、D0..D7、STOP 采样前复位并恢复 |
| 毛刺 | 偏离中心的毛刺不影响该用例；中心毛刺改变数据但不报 framing error |
| 接口与周期 | busy、事件单拍且互斥、无 valid 时数据保持、精确完成周期 |
| 防假通过 | 自动评分、100 ms watchdog、脚本退出码和本次结果文件 |

串行激励按 `1e9/BAUD` 生成，不复用 RTL 的整数分频；数据评分按发送内容
独立生成期望值。周期检查另外观察同步下降沿和 FSM，以捕获计数偏一拍。

## 2. 推荐：PowerShell 一键测试

```powershell
Set-Location D:\Code\zynq_vibration_monitor
.\sim\run_uart_rx.ps1 -Simulator modelsim
.\sim\run_uart_rx.ps1 -Simulator xsim
# 或一次运行两套
.\sim\run_uart_rx.ps1 -Simulator both
```

默认路径为本机的 `D:/modelsim/win64` 和 `D:/Xilinx/Vivado/2020.2/bin`。
其他安装位置可用 `-ModelSimBin`、`-VivadoBin` 指定。
如果 Windows 执行策略禁止脚本，可使用仅本次新进程生效的启动方式：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\sim\run_uart_rx.ps1" -Simulator both
```

该命令不永久修改系统或用户执行策略。也可使用后文手动流程；若组策略强制
限制脚本运行，先用 `Get-ExecutionPolicy -List` 确认来源，不擅自改动组织策略。

脚本会先把旧结果标记 NOT_RUN，再编译、展开和仿真；检查工具退出码与新
结果文件，防止把旧 PASS 当成当前结果。不调用综合、实现或烧录。

```text
build/modelsim_uart_rx/uart_rx_result.txt
build/modelsim_uart_rx/transcript.log
build/modelsim_uart_rx/vsim.wlf
build/xsim_uart_rx/uart_rx_result.txt
build/xsim_uart_rx/xvlog.log
build/xsim_uart_rx/xelab.log
build/xsim_uart_rx/xsim.log
build/xsim_uart_rx/tb_uart_rx_sim.wdb
```

## 3. ModelSim 图形界面

启动 ModelSim，在 Transcript 输入，路径用正斜杠：

```tcl
file mkdir D:/Code/zynq_vibration_monitor/build/modelsim_uart_rx
cd D:/Code/zynq_vibration_monitor/build/modelsim_uart_rx
# 首次运行需要 vlib；已有 work 时跳过
vlib work
vmap work D:/Code/zynq_vibration_monitor/build/modelsim_uart_rx/work
vlog -work work D:/Code/zynq_vibration_monitor/rtl/uart_rx.v D:/Code/zynq_vibration_monitor/sim/tb/tb_uart_rx.v
vsim -onfinish stop -voptargs=+acc work.tb_uart_rx
do D:/Code/zynq_vibration_monitor/sim/modelsim/wave_uart_rx.do
run -all
examine -radix unsigned /tb_uart_rx/test_done
examine -radix unsigned /tb_uart_rx/error_count
```

最后两个值应为 1、0，并出现 PASS 汇总。`$finish` 的停止提示只是结束通知，
不能单凭此判断通过。出现 FAIL、watchdog 或非零错误数均未通过。
查看最初一个字节可执行：

```tcl
restart -f
run 150 us
wave zoom full
```

完整重跑使用 `restart -f`、`run -all`。FSM 数值：0 WAIT_HIGH、1 IDLE、
2 START、3 DATA、4 STOP。重点看 rx_i/rx_meta/rx_sync、baud_cnt、bit_idx、
shift_reg、data_o、valid_o、framing_error_o、busy_o。valid/error 脉冲宽为 20 ns。
批处理 run_uart_rx.do 会退出 ModelSim；想保留 GUI 请使用上述手动流程。

## 4. Vivado 图形界面行为仿真

1. 在 `vivado_project/uart_rx_stage1` 新建 RTL Project，选择实际芯片完整 part。
   现有资料不能确认速度等级等全部信息，此处不代填。
2. Add Sources -> Add or Create Design Sources：添加 `rtl/uart_rx.v`。
3. Add Sources -> Add or Create Simulation Sources：添加 `sim/tb/tb_uart_rx.v`。
4. 在 Simulation Sources 中将 `tb_uart_rx` 设为 Top，文件类型保持 Verilog。
5. UART RX 独立测试不要添加板级 XDC：原 top_candidate.xdc 现已迁移为 top.xdc，面向板级 top，端口与 uart_rx 不同；
   行为仿真的时钟和串口激励由 TB 产生。
6. Run Simulation -> Run Behavioral Simulation。
7. Scopes 中选 `tb_uart_rx/main_case/dut`，将需要的信号 Add to Wave。
8. 在仿真 Tcl Console 执行：

```tcl
restart
log_wave -r /tb_uart_rx/main_case/dut/*
log_wave /tb_uart_rx/main_case/rx_i /tb_uart_rx/main_case/rst
run all
get_value -radix unsigned /tb_uart_rx/test_done
get_value -radix unsigned /tb_uart_rx/error_count
```

验收同样为 PASS 汇总、test_done=1、error_count=0。GUI 工程日志在自身 .sim
目录，与脚本的 build/xsim_uart_rx 不同。本轮执行了 XSim 命令行行为仿真，
没有实际操作 GUI；上述为 GUI 复现和波形观察步骤。

## 5. Vivado XSim 不建工程的手动流程

在 PowerShell 顺序执行，每一步成功后再继续：

```powershell
Set-Location D:\Code\zynq_vibration_monitor
New-Item -ItemType Directory -Force build/xsim_uart_rx | Out-Null
Set-Location build/xsim_uart_rx
& 'D:\Xilinx\Vivado\2020.2\bin\xvlog.bat' 'D:/Code/zynq_vibration_monitor/rtl/uart_rx.v' 'D:/Code/zynq_vibration_monitor/sim/tb/tb_uart_rx.v'
& 'D:\Xilinx\Vivado\2020.2\bin\xelab.bat' -debug all work.tb_uart_rx -s tb_uart_rx_sim
& 'D:\Xilinx\Vivado\2020.2\bin\xsim.bat' tb_uart_rx_sim -onfinish stop -tclbatch 'D:/Code/zynq_vibration_monitor/sim/xsim/run_uart_rx.tcl'
Get-Content uart_rx_result.txt
```

推荐使用一键脚本，它自动检查退出码并作废旧结果。此手动流程无须 FPGA part
或 XDC。`-tclbatch` 路径用正斜杠，避免旧版 Windows 包装器的 Tcl 转义问题。
AMD 参考：[UG900 batch simulation](https://docs.amd.com/r/2023.2-English/ug900-vivado-logic-simulation/Using-a-tclbatch-File)、
[UG835 get_value](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/get_value)。
本项目命令行入口已在本机 2020.2 验证。

## 6. 待你确认的硬件事项

- 核心板/底板版本与 FPGA 完整丝印。
- Bank34/VCCIO、Bank35 实测电压及选择电阻实际焊接情况。
- X1 实际 50 MHz 输出；原理图连接 U18，不能继续用 U13。
- J3 pin 1 方向、地脚和 P1 跳帽，避免多输出驱动 RX。
- STM32 TX 与 USB-UART 的实际逻辑电平。

上述没有实测证据。当前没有 board top、板级复位或 TX 回传，不应将 uart_rx
直接当板级顶层烧录。仿真不能验证电压、真实亚稳态或物理约束。
