# 第三阶段验证记录

日期：2026-10-27，时区 Asia/Shanghai。用户接受第二阶段、继续暂缓上板，并授权第三阶段。实施中用户补充 `stm32/Libraries`；核查后它包含 CMSIS 与标准库，没有完整 Keil 应用模板。本轮基于实际库建立独立应用工程。

后续更新：2026-10-28 按新增核心板/扩展板资料，将传感器改为 I2C2/PB10/PB11，驱动现名 bsp_i2c。下面保留第三阶段原始结果；当前引脚、再次编译结果和资料依据见 `../docs/stm32_board_review.md`。

同日后续已按用户要求完成正式 FPGA 约束与独立综合/实现检查，见 `../docs/fpga_constraints.md`。下面“未综合/实现”描述的是初次第三阶段交付范围，不能覆盖该后续结果；仍未生成比特流或上板。

## 完成范围

实现 FPGA 上电复位、回传队列与控制、通信核心和顶层，配套四项自检；实现 PC 原始记录/解码/离线验收工具；实现 STM32 标准库固件、两个 Keil 目标和可移植测试。输入十字节布局不变；输出通过编译参数互斥选择整包或单字节 ACK。

未进行真实串口收发、传感器读取、Vivado 综合/实现、时序签核、下载或板测。已有 `vivado_project`、候选 XDC、RX/TX/解析器及前两阶段 TB 均未作本阶段修改。顶层仅 PL，未引入 PS/AXI/Linux/PYNQ 或 FIR。

## FPGA 实际执行结果

工具：ModelSim SE-64 2020.4，Vivado XSim 2020.2。以下四种测试均已通过两个仿真器实际执行；根目录为 `D:\Code\zynq_vibration_monitor`。最终 core/top 重跑使用的命令为：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage3.ps1 -Simulator both -Test monitor_core
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage3.ps1 -Simulator both -Test top
```

前两个单元已分别在 ModelSim、XSim 执行，可按以下命令复现；一次执行全部四项可省略 `-Test`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage3.ps1 -Simulator both -Test power_on_reset
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage3.ps1 -Simulator both -Test return_controller
```

| 测试 | ModelSim 当前结果写入时间 | XSim 当前结果写入时间 | 两者结果 |
|---|---|---|---|
| power_on_reset | 20:25:03 | 20:28:40 | PASS checks=124 errors=0 |
| return_controller | 20:25:05 | 20:28:48 | PASS checks=78 errors=0 |
| monitor_core | 20:36:46 | 20:36:56 | PASS checks=255 errors=0 |
| top | 20:37:06 | 20:37:22 | PASS checks=272 errors=0 |

结果和日志分别在 `build/modelsim_stage3/<测试>/`、`build/xsim_stage3/<测试>/`。脚本检查工具退出码、完成标志、TB 错误数与新结果标记。所有所测用例错误数为零，不据此声称任意参数和任意输入均已形式化证明。

复位单元验证 1/16 拍和多次重触发。回传单元在深度 2 下制造反压、满队列丢新包、同拍出入队，验证独立快照、两个模式和复位恢复；集成使用默认深度 4。其它队列深度未逐一测试。

串行集成使用 50 MHz 时钟、标称 115200 的逐位激励及独立输出位采样器。先连续发送 16 个 4 ms 间隔的包，再注入坏头/坏校验、截断、BREAK、重复序号和载荷包头。top 最终每种模式接纳 24 个合法包，整包返回 240 字节，ACK 返回 24 字节；诊断应有校验错 1、超时 1、UART 错 1、序号不连续 3，回传丢弃为 0。core 额外检查发送途中复位和后续恢复；该项输出字节统计包含复位前活动，不解释为 26 个完整包。

## PC 与固件软件实际结果

本机解释器为 Python 3.12.14。以下 PowerShell 变量仅为命令简写：

```powershell
$taskPython = 'C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $taskPython -X utf8 -m unittest discover -s host -p test_protocol.py -v
& $taskPython -X utf8 host/check_stage3_captures.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stm32\test_portable.ps1 -Python $taskPython
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stm32\build_keil.ps1
```

| 检查 | 实际结果与证据 |
|---|---|
| PC 单元测试 | 7 项通过；正常/损坏/分片/插入删除/截断恢复/序号/日志/拒绝覆盖/失败出口 |
| ModelSim 捕获→PC | frame=24，240 字节，逐项匹配期望；ACK=24，24 字节 |
| XSim 捕获→PC | 同上；捕获还与 ModelSim 逐字节相等 |
| PC 日志输出 | `build/pc_stage3/run_20261027_203935_323867/` 下四组原始二进制、CSV、JSON |
| C 可移植自检 | GCC 16.1，`-std=c99 -Wall -Wextra -Werror`；PASS values=65536 vectors=32 errors=0 |
| C→Python 交叉解码 | 32 包的序号和三轴全部匹配；`build/stm32_portable/vectors.bin` |
| Keil FixedSource | 20:44:05 全量重建，退出码 0，0 错误、0 警告 |
| Keil SensorSource | 20:44:08 全量重建，退出码 0，0 错误、0 警告 |

两个 Keil 目标实际使用 MDK-ARM Lite 5.36 的 ARM Compiler 5.06 update 7 build 960，链接结果均为 Code=3852、RO-data=280、RW-data=60、ZI-data=1060 字节。目标按 Flash 64 KiB、SRAM 20 KiB 建立；链接不是运行测试。日志位于 `build/stm32/<目标>/keil_build.log`，产物为 vibration_monitor.axf；依赖文件确认实际包含用户库的 stm32f10x.h/core_cm3.h/system_stm32f10x.h。

C 模拟依赖测试覆盖固定源 4 ms 调度、同毫秒去重、时间回绕、发送失败后的序号缺口、迟到提示、WHO_AM_I 错误、配置回读不一致、无数据就绪、六字节补码、I2C 失败及一秒后重初始化。真实标准库 BSP 只经编译/人工时序核查，未以此模拟测试声称已验证 STM32 寄存器行为。

PC 测试中的 `FAIL capture: ACK 模式出现非 06 字节` 和数量不匹配是预期失败出口，单元测试要求返回错误。整包捕获 seq_discontinuities=3、duplicates=1、gap_mod256_total=2 也为故意跳号/重复的预期结果，不能删掉再声称正常连续流。

在线依赖 pyserial 当前未安装；没有打开 COM 口，未验证在线分支。离线 CSV 时间戳为 0，不冒充真实采样时间。

## 纠错与环境限制

1. 初次串行 TB 排空等待仅 12 个位时间，足以等一个字节、不足以等完整十字节；已改为 110 个位时间，保留逐字节与计数检查，再运行通过。
2. 早期 XSim 对循环变量负值直接作为 task 参数的激励产生 X，ModelSim 未出现。定位到输入载荷已经含 X 后，将激励改为显式 16 位寄存器和有界补码运算，并增加发送前未知位断言。最终 core/top 两个仿真器均重跑通过，没有修改 RX 或解析器来迁就激励。
3. GCC 首次缺少同目录运行库的 PATH，编译子进程静默失败；脚本仅在当前进程临时添加编译器目录并恢复，最终编译和运行通过。
4. 自建 Keil XML 初版输出目录、缺失的 VariousControls 空字段导致路径或宏解析失败；已修正为本地相对路径、完整字段和兼容的 UTF-8 XML。最终一键脚本全量重建两个目标通过，未复制第三方示例代码。
5. 沙箱内旧版 ModelSim/ARMCC 运行库加载受限，相关仿真与 Keil 编译使用获准的沙箱外本机工具调用；只生成本地测试产物。Python 初次临时目录写入受限，受准调用后 7 项通过；最终还在仅本次进程设置 TMP/TEMP 指向 `build/python_temp` 的沙箱调用中复验通过，未改永久环境。

## 文件清单与保护

| 文件 | 本阶段职责 |
|---|---|
| rtl/power_on_reset.v、return_controller.v、monitor_core.v、top.v | 上电复位、等待队列与回传、可复位核心、三端口 PL 顶层 |
| sim/tb/tb_power_on_reset.v、tb_return_controller.v、tb_monitor_core.v、tb_top.v | 四个模块的正常/异常/恢复自检 |
| sim/tb/stage3_serial_case.v | 核心/顶层共用逐位激励、独立解码与捕获；不是可综合模块 |
| sim/run_stage3.ps1、modelsim/run_stage3.do、xsim/run_stage3.tcl | 双仿真器执行、波形与成功判定 |
| host/protocol.py、capture.py、test_protocol.py、check_stage3_captures.py | 独立协议、日志、软件测试和跨仿真器验收 |
| host/requirements.txt、README.md | 在线依赖及使用限制 |
| stm32/app/*.c、*.h | 入口、应用采集调度和十字节组包 |
| stm32/bsp/*.c、*.h | 标准库时基/USART/I2C 与 MPU6050 驱动 |
| stm32/config/stm32f10x_conf.h、keil/vibration_monitor.uvprojx | 标准库配置与两目标工程 |
| stm32/tests/test_portable.c、check_vectors.py | 应用模拟依赖自检与 C/Python 对照 |
| stm32/test_portable.ps1、build_keil.ps1、README.md | 测试、重建入口和工程职责 |
| docs/stage3_design.md、stage3_test_guide.md、本记录 | 中文设计、操作与实际证据 |
| README.md、docs/project_context.md、next_task.md、report/ai_devlog.md | 更新当前进度与后续边界 |
| .gitignore | 忽略授权未核实的本地厂商库和生成缓存，保留新增应用源码 |

库文件哈希清单为 `build/stm32_portable/vendor_hashes.csv`；建工程前后比较修改数为 0。库仍在用户目录，本阶段没有删除或翻译厂商源文件。以下 SHA256 与本阶段开始时相同：

```text
rtl/uart_rx.v
4B61664EBEA1E0AF3F802355C77561BBECCDFB80E59C2F96AC471277B7C5DFDC
sim/tb/tb_uart_rx.v
CD71CBF4627F64C40939923276AC2A42C77565D585E8FFE822D5E9F730BC2A3F
rtl/packet_parser.v
D56E96D05F2207C83FEA175D991D6243CF9F324C81C468876726CA3A20D3BB84
rtl/uart_tx.v
F922500776879394F7C78092437AC3E1193D5DE2EAC443F74B223087FC40D596
```

git diff --check 通过；另扫描 60 个文本源文件，UTF-8、替换字符和行末空白检查通过。三个新增 PowerShell 入口的语法与 UTF-8 BOM 检查通过，Keil XML 可解析。Windows 换行转换提示不代表功能失败。新增说明性注释与 Markdown 为中文。仿真/固件产物只写入被忽略的 build；Keil 自动生成的 DebugConfig 位于新工程目录并被忽略，没有修改原有调试/烧录配置。不提交或推送仓库。

## 尚待验证

上电复位采用寄存器配置初值和时钟计数，不是欠压复位监测器，尚未经本轮 Vivado 综合核查。当前顶层未导出诊断引脚，综合时未使用计数器可能被优化；仿真中的层次计数不能直接等同于可从 PC 读取的板级状态。

完整 FPGA part、实际时钟与 Bank 电压、跳线、电平、STM32 晶振/I2C 接线和 MPU6050 实际 250 Hz 时序均待实物确认。I2C 恢复不保证解决持续线路故障，无 FIFO 时仍可能漏掉未读取的传感器样本。XOR 与模 256 序号也不能证明绝对无误码/无丢样。

第三阶段软件和仿真成果已具备评审条件；真实原始日志这一板级里程碑按用户要求暂缓。后续进入 FIR 前应另行决定如何补齐实物证据，不能以本记录替代传感器测量。
