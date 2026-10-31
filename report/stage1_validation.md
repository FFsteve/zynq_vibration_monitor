# 第一阶段验证记录

日期：2026-10-27，时区 Asia/Shanghai。范围仅为 UART RX 字节层和已确认的原理图纠错。没有实现包解析器、UART TX、STM32 代码或板级顶层；10 字节协议保持草案状态，未作修改或冻结。

## 实际执行的验证

以下为第一阶段原始实现的最终回归记录。在 `D:/Code/zynq_vibration_monitor` 执行：

```powershell
.\sim\run_uart_rx.ps1 -Simulator both
```

ModelSim 于 11:52:04 完成，XSim 于 11:52:13 完成，进程退出码为 0。入口脚本检查工具退出码及本次新结果，Tcl 另检查 test_done=1、error_count=0。

| 工具与配置 | 接收字节数 | 预期停止位错误事件 | 测试失败数 |
|---|---:|---:|---:|
| ModelSim SE-64 2020.4，50 MHz / 115200 | 699 | 4 | 0 |
| ModelSim SE-64 2020.4，50 MHz / 1500000，奇数分频 33 | 699 | 4 | 0 |
| Vivado XSim 2020.2，50 MHz / 115200 | 699 | 4 | 0 |
| Vivado XSim 2020.2，50 MHz / 1500000，奇数分频 33 | 699 | 4 | 0 |

两套仿真器均输出下列真实日志，英文标记保留以便自动解析：

```text
PASS tb_uart_rx: bytes=1398 framing=8 errors=0
```

两者结束仿真时间均为 64291282679 ps，约 64.2913 ms。每组主动注入三次坏停止位和一次 BREAK，因此错误事件是预期行为。ModelSim 最终编译与仿真均为 0 错误、0 警告；XSim 编译、展开和运行没有错误。无须厂商原语库或 FPGA 器件型号。

本地生成的证据已被 Git 忽略：

- `build/modelsim_uart_rx/transcript.log`
- `build/modelsim_uart_rx/uart_rx_result.txt`
- `build/modelsim_uart_rx/vsim.wlf`
- `build/xsim_uart_rx/xvlog.log`
- `build/xsim_uart_rx/xelab.log`
- `build/xsim_uart_rx/xsim.log`
- `build/xsim_uart_rx/uart_rx_result.txt`
- `build/xsim_uart_rx/tb_uart_rx_sim.wdb`

`git diff --check` 退出码为 0；Git 仅提示既有 Windows 换行转换，没有空白错误。生成产物和厂商 PDF 仍被忽略。覆盖范围与命令详见 `docs/stage1_test_guide.md`。

下列 SHA256 对应原始英文注释版本的已验证源码；中文注释版本会改变文件哈希，但不改变代码逻辑：

```text
rtl/uart_rx.v
21D8C8714E4A14112446BB1E0C8D7D362176D44C40359228238A22B69C411C42
sim/tb/tb_uart_rx.v
91276F19161C2A59F738C30863AB9C8E79B775F4E306932BD285BBC5D1B01A22
```

## 原理图依据与验证边界

已渲染并核对核心板 PDF 第 3、7、10 页和底板 PDF 第 1、5 页。时钟路径为 X1 -> R7 -> PL_GCLK -> U18（Bank34 MRCC），此前 U13 的描述错误。UART 的 K14/M15 路径与图纸一致。引脚文档记录了连接器、地/电源脚和图示 Bank 电源选择。

这些是图纸结论，不是实物测量。以下内容尚未执行或确认：

- ModelSim、Vivado 交互式图形界面操作；已提供操作步骤。
- Vivado 综合、布局布线、时序收敛、DRC 和实现后的跨时钟域检查。
- 将候选 XDC 应用到最终板级顶层；目前没有该顶层。
- 实际 PCB 版本、芯片型号、VCCO、振荡器、跳线、传感器采集、UART 电气与板测。

RTL 需要同步复位。两级同步降低跨时钟域风险，但数字仿真不能验证真实亚稳态或平均无故障时间。单点采样不能纠正噪声，+/-2% 测试结果也不是对全部参数的保证。

## 第一阶段文件清单

| 文件 | 操作 | 职责 |
|---|---|---|
| rtl/uart_rx.v | 新增 | 同步复位的 8N1 接收、异步同步、停止位检查与恢复 |
| sim/tb/tb_uart_rx.v | 新增 | 两组参数的自检回归和超时保护 |
| sim/run_uart_rx.ps1 | 新增 | 调度两套仿真器，检查退出码和新结果 |
| sim/modelsim/run_uart_rx.do | 新增 | ModelSim 编译、加载、运行、验收和退出 |
| sim/modelsim/wave_uart_rx.do | 新增 | 图形界面观察信号 |
| sim/xsim/run_uart_rx.tcl | 新增 | XSim 波形记录、运行与结果检查 |
| docs/uart_rx_design.md | 新增 | 接口、寄存器、状态机、精确时序和限制 |
| docs/stage1_test_guide.md | 新增 | 中文测试范围、命令行、图形界面和硬件检查步骤 |
| report/stage1_validation.md | 新增 | 实际证据、验证边界和本清单 |
| constr/top_candidate.xdc | 修改 | U13 纠正为 U18，说明未来顶层适用范围 |
| docs/hardware_pinmap.md | 修改 | 纠正时钟路径，补充原理图依据及未知项 |
| docs/project_context.md | 修改 | 更新进度，保留协议草案 |
| docs/next_task.md | 修改 | 第二阶段入口与协议审批要求 |
| README.md | 修改 | 导航和复现命令 |
| report/ai_devlog.md | 修改 | 决策、纠错、命令、证据和待办 |

## 已解决问题与待处理清理

1. 沙箱内 ModelSim 启动出现 Windows DLL 重定位错误；获准在沙箱外启动后正常，版本为 2020.4。
2. 初版 ModelSim 宏使用 Tcl `info script` 得到了内部脚本路径，已改为显式传入并验证仓库根目录。后续仿真输出均在仓库内。
3. XSim 2020.2 的 Windows 包装器将 Tcl 路径反斜杠作转义；改用正斜杠后正常。NOT_RUN 标记成功阻止了失败启动被误判为通过。
4. 初次路径问题在 `D:/build/modelsim_uart_rx` 留下 modelsim.ini、transcript.log 和 work/_info。自动审批因项目禁止未经批准的删除命令而拒绝清理；没有执行删除或绕过限制。该目录等待明确批准，不影响项目。

下一步由用户评审第一阶段并完成实物检查，再批准、冻结协议并进入第二阶段。不得声称已具备上板条件。

## 中文文档与注释修订

根据用户要求，将第一阶段 Markdown 文档和 RTL、TB、脚本的说明性注释统一为中文，并将该规则写入 `AGENTS.md`。保留文件名、代码标识符、命令、日志字符串及综合工具指令。PowerShell 脚本采用带 BOM 的 UTF-8，兼容 Windows PowerShell 5.1。

本次语言修订检查结果：

- 将修改前的源码分词结果保存在 `build/chinese_translation/baseline.json`，去除注释和空白后逐项比较，RTL 和 TB 的全部代码词元完全一致，包含日志字符串在内。
- 过滤说明性注释后，PowerShell、ModelSim、XSim 和 XDC 的可执行内容完全一致。
- ModelSim 2020.4 重新编译通过，0 错误、0 警告，完成时间为 2026-10-27 18:49:15。
- Vivado XSim 2020.2 的 xvlog 重新编译通过，未报告错误。
- PowerShell 脚本语法检查通过，确认文件带 UTF-8 BOM；说明性注释扫描与 `git diff --check` 通过。
- 本次仅作编码与编译检查，没有重新展开和运行完整回归；上方 1398 字节的记录仍对应第一阶段原始回归，未冒充本次新结果。

本次编译在各自目录执行以下命令，未改动原回归证据目录：

```powershell
# 工作目录：build/chinese_translation/modelsim
& 'D:\modelsim\win64\vlib.exe' work
& 'D:\modelsim\win64\vlog.exe' -work work 'D:/Code/zynq_vibration_monitor/rtl/uart_rx.v' 'D:/Code/zynq_vibration_monitor/sim/tb/tb_uart_rx.v'
# 工作目录：build/chinese_translation/xsim
& 'D:\Xilinx\Vivado\2020.2\bin\xvlog.bat' 'D:/Code/zynq_vibration_monitor/rtl/uart_rx.v' 'D:/Code/zynq_vibration_monitor/sim/tb/tb_uart_rx.v'
```

两套编译日志分别为 `build/chinese_translation/modelsim/compile.log` 和 `build/chinese_translation/xsim/compile.log`。中文注释版本的 SHA256 为：

```text
rtl/uart_rx.v
4B61664EBEA1E0AF3F802355C77561BBECCDFB80E59C2F96AC471277B7C5DFDC
sim/tb/tb_uart_rx.v
CD71CBF4627F64C40939923276AC2A42C77565D585E8FFE822D5E9F730BC2A3F
```

本次额外更新 `AGENTS.md`，用于长期保存中文文档与注释规则。第一阶段各文件的语言修订不改变原有职责。
