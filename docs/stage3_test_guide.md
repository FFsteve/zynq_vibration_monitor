# 第三阶段测试指南：原始数据通信闭环

本阶段按用户要求暂缓上板。以下命令在 `D:\Code\zynq_vibration_monitor` 执行，均不连接或烧录板卡。设计见 `stage3_design.md`，已执行结果见 `../report/stage3_validation.md`。

后续更新：2026-10-28 已额外完成正式 XDC 和隔离的综合/实现检查，见 `fpga_constraints.md`；本指南下述 XSim 步骤仍仅为行为仿真，不应与那次实现检查混淆。

## 先运行 FPGA 自检

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage3.ps1 -Simulator both
```

这是仅对本次 PowerShell 进程生效的执行策略，不需要修改系统永久策略。工具默认目录为 `D:\modelsim\win64` 和 `D:\Xilinx\Vivado\2020.2\bin`；不同安装位置用 `-ModelSimBin`、`-VivadoBin` 指定。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage3.ps1 -Simulator modelsim -Test return_controller
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage3.ps1 -Simulator xsim -Test top
```

| 测试名称 | 内容与验收标准 | 当前通过标记 |
|---|---|---|
| power_on_reset | 保持 1/16 拍、启动初值、重新触发、计时途中重启；释放边界准确 | checks=124 errors=0 |
| return_controller | 两种输出模式、快照、反压、满队列丢新包、满时同拍出入队、复位清空与恢复 | checks=78 errors=0 |
| monitor_core | 真实串行输入输出、250 包/s、坏头/坏校验/截断/BREAK 恢复、序号与负数、发送中复位 | checks=255 errors=0 |
| top | 两套完整顶层同时验证 ACK/整包，含上电复位；每种模式接收 24 个合法包 | checks=272 errors=0 |

每项须同时满足工具退出码为 0、TB 完成、错误数为 0、当前结果文件为 PASS。脚本先作废旧结果；看见历史 PASS 文件不能算本次成功。故意注入的坏包会增加设计诊断计数，并不等于 TB 失败。

输出目录为 `build/modelsim_stage3/<测试名称>/` 和 `build/xsim_stage3/<测试名称>/`，含日志、结果文本和波形。顶层整包捕获为 `top_frame_capture.bin`，ACK 捕获为 `top_ack_capture.bin`，分别有独立期望 CSV。

## ModelSim 查看波形

先运行上述自动自检，再从 ModelSim 菜单 File → Open 打开 `build/modelsim_stage3/top/vsim.wlf`。也可在 Transcript 输入：

```tcl
vsim -view D:/Code/zynq_vibration_monitor/build/modelsim_stage3/top/vsim.wlf
add wave -r /tb_top/*
```

重点展开 `frame_case` 和 `ack_case` 中的 `g_top.dut`。观察 `rst`、`pl_rx`、`pl_tx`、`u_core.u_parser.frame_valid_o`、`u_core.u_return.state`、`count`、`active_packet`、`u_core.tx_valid`、`tx_ready`、`tx_done`。独立回传控制用例还应观察 dropped/accepted/completed 和 overflow：满时拒收的新包不得改变已有顺序。

批处理 `.do` 最后会退出 ModelSim；需要交互观察时打开保存的 WLF 即可。命令行完成本轮自检已经足以判定通过，波形用于理解和定位。

## Vivado 查看同一套测试

最直接的方法是使用 `-Simulator xsim`，它通过 Vivado 自带 xvlog、xelab、xsim 运行，不改变现有 `vivado_project`。

也可在 Vivado 图形界面操作：

1. 新建独立的仿真工程，目录例如 `build/vivado_stage3_gui`。器件选择必须对应确认的实物；本轮尚未确认完整 part，不能因此执行板级验收。
2. 添加 Design Sources：`rtl` 下七个模块。Simulation Sources 添加 `stage3_serial_case.v` 及四个 `tb_*.v`：`tb_power_on_reset`、`tb_return_controller`、`tb_monitor_core`、`tb_top`。不要把 TB 设为综合顶层。
3. 在 Simulation Sources 中逐项将对应 TB 设为仿真顶层，Run Behavioral Simulation，然后在 Tcl Console 输入 `run all`。核心/顶层仿真约到 80 ms，默认 1000 ns 远远不够。
4. 检查控制台对应 PASS 行；加入上述波形。仿真顶层 `tb_top` 与设计顶层 `top` 是两个不同对象。

行为仿真不使用候选 XDC，也不运行综合、实现、时序签核或生成比特流。本轮实际执行的是脚本化 XSim，未操作上述 GUI 路径。

## PC 协议与仿真捕获验收

需要 Python 3.10 或以上；离线部分仅用标准库。以下 `python` 应指向所选解释器；本机执行证据使用 Codex 随附 Python，完整路径见验证记录。

```powershell
python -X utf8 -m unittest discover -s host -p test_protocol.py -v
python -X utf8 host/check_stage3_captures.py
```

第二条要求两种仿真器的 `top` 自检都已完成。它把两套捕获分别送入实际 PC 工具，逐样本比对期望 CSV，再逐字节比较两个仿真器的捕获。每种模式应有 24 条响应；整包 240 字节，ACK 24 字节。结果写入新的 `build/pc_stage3/run_<时间>/`，不覆盖旧证据。

输出包括原始 `capture.bin`、`samples.csv` 和 `stats.json`。本次专门注入跳号和重复，因此整包统计应为 seq_discontinuities=3、duplicates=1、gap_mod256_total=2；这是预期诊断，不应删掉这些记录来追求全零。ACK 只有数量，不能证明三轴内容正确。

## STM32 软件测试与 Keil

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stm32\test_portable.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stm32\build_keil.ps1
```

第一条默认使用 `D:\msys2\ucrt64\bin\gcc.exe`；可用 `-Gcc` 和 `-Python` 更换。它在 PC 上模拟 I2C/时钟/UART 依赖，测试应用与组包，再用 Python 解码实际 C 生成的 32 包。它不模拟 STM32 寄存器或电气线路。

第二条默认使用本机 Keil，重建 FixedSource 与 SensorSource；可用 `-UV4` 或 `-Target` 指定。要求你提供的 `stm32/Libraries` 存在。输出和日志在 `build/stm32/<目标>/`，验收为 0 错误、0 警告。

也可以双击 `stm32/keil/vibration_monitor.uvprojx`，选择 FixedSource 或 SensorSource，使用 Project → Rebuild all target files。不要点击 Download 或启动硬件调试。编译器使用 ARM Compiler 5，标准库不替换为 HAL。固定模式用于未来先检查链路，传感器模式用于后续验证 WHO_AM_I 和采样。详细职责与配置见 `../stm32/README.md`。

## 暂缓的实物验收

本轮没有真实 MPU6050 数据、COM 口记录、综合实现或板测证据。以后获授权后，先确认板型、电压、跳线、STM32 晶振和完整 FPGA part，再依次做固定包 ACK、固定包整包回传、传感器整包采集。真实采样率、静止重力方向、负数、转动变化、连续日志和故障恢复都需要实测；此处离线 PASS 不能替代这些步骤。
