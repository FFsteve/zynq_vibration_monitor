# 第二阶段验证记录

日期：2026-10-27，时区 Asia/Shanghai。用户接受第一阶段并授权第二阶段，同时明确暂缓上板测试。

## 完成范围

本轮实现 `packet_parser`、`uart_tx` 和各自自检 TB，另增加纯仿真的 TX→RX→解析器链路自检。沿用原十字节布局，明确 2 ms 字节超时、滑动恢复、整包原子提交和序号诊断。详细接口与周期见 `docs/stage2_design.md`。

用户授权的是第二阶段实施；2 ms 边界、序号仅诊断等属于已说明的实现选择，不代表实物测量或用户曾逐项单独确认。后续变更协议仍需批准。

本轮不修改第一阶段 RX 与 TB、不新增板级顶层、STM32、PC 程序、FIR 或 PS，也不修改 XDC、Vivado 项目缓存或烧录设置。

## 实际命令与结果

在 `D:/Code/zynq_vibration_monitor` 分别执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage2.ps1 -Simulator modelsim
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage2.ps1 -Simulator xsim
```

两次最终命令均以退出码 0 完成。ModelSim SE-64 2020.4 的最终运行时间为 19:33:39 至 19:33:50；Vivado XSim 2020.2 于 19:34:14、19:34:27、19:34:35 依次完成三项测试。ModelSim 编译与仿真报告 0 错误、0 警告；XSim 编译、展开、运行完成，未报告错误。

| 仿真器 | 测试 | 当前结果标记 |
|---|---|---|
| ModelSim 2020.4 | 解析器 | PASS packet_parser checks=171 errors=0 |
| ModelSim 2020.4 | UART TX | PASS uart_tx checks=2931922 errors=0 |
| ModelSim 2020.4 | 串行模块链路 | PASS uart_packet_link checks=14 errors=0 |
| XSim 2020.2 | 解析器 | PASS packet_parser checks=171 errors=0 |
| XSim 2020.2 | UART TX | PASS uart_tx checks=2931922 errors=0 |
| XSim 2020.2 | 串行模块链路 | PASS uart_packet_link checks=14 errors=0 |

两套仿真器的统计和结束仿真时刻一致：

- 解析器：118 个合法包；30 次预期候选校验错误、4 次预期超时、12 次序号不连续诊断；仿真结束于 46380 ns。
- TX：两组参数共接收 686 个请求，完整发送 666 帧，20 帧由复位按预期终止；每组均为 343/333/10。默认每位 434 拍，另一组每位 33 拍；仿真结束于 29319101 ns。
- 模块链路：TX 和 RX 均为 103 字节，提交 8 个合法包，预期 UART 错误、校验错误、超时各一次；仿真结束于 13570820 ns。

这些故意注入的诊断事件不是测试失败。入口脚本作废旧结果并检查退出码和新结果，仿真脚本另检查 TB 的 test_done=1、error_count=0。

## 验证方法与边界

解析器的期望样本直接来自激励登记，不复用 RTL 滑动窗口算法。检查所有包字节位置的损坏、载荷位置的插入/删除、所有非空截断长度、完整包中的包头序列、连续每拍一字节、正负极值、大端、序号回绕/跳号/重复和复位。

单元测试用 32 拍超时，逐拍检查阈值前一拍、阈值、阈值后一拍，以及边界新字节保留和 UART 错误优先级；链路用默认 100000 拍验证实际 2 ms 超时。

TX 参考模型仅观察外部握手、数据和经过的周期，不读取内部状态/计数器。每个周期比较串行电平、ready、busy 和 done，覆盖全部字节、完整停止位、连续握手、忙时短请求、持续有效请求、输入修改、所有串行阶段的复位和恢复。

串行链路使用实际 TX、第一阶段 RX 和解析器，覆盖模块间接口及错误传播；它不替代独立 TX 自检，不是板级顶层，也不是已经验证的 PC 回传系统。

没有运行综合、布局布线、时序收敛、DRC、交互式 GUI 或板测。未确认实际 PCB、电气、器件和跳线。XOR 不能检出所有损坏，未转义包头也可能形成偶然伪包；本轮结果只支持列明用例和参数配置。

## 原始证据

每个测试对应以下目录中的 `<测试名>_result.txt`：

```text
build/modelsim_stage2/packet_parser/
build/modelsim_stage2/uart_tx/
build/modelsim_stage2/uart_packet_link/
build/xsim_stage2/packet_parser/
build/xsim_stage2/uart_tx/
build/xsim_stage2/uart_packet_link/
```

ModelSim 的 `transcript.log`、XSim 的 `xvlog.log`、`xelab.log`、`xsim.log` 保存工具与自检输出。对应 wlf/wdb 可用于回看波形。所有生成文件仍在已忽略的 build 中。

## 开发中发现并纠正的问题

首次 ModelSim 解析器测试发现 TB 把“截断后只剩一个 A5”也登记为一次候选校验错误。单个 A5 尚未构成 A5 5A 包头，因此不应计数。该多计一次的期望导致后续检查连带失败。已只修正该用例的期望计数，未改 RTL、放宽输出保持或恢复检查；随后重新执行三项 ModelSim 和三项 XSim，全部通过。首次失败没有被计为成功。

## 本轮文件清单

| 文件 | 操作 | 用途 |
|---|---|---|
| rtl/packet_parser.v | 新增 | 原子提交三轴、滑动搜索、校验、超时与序号诊断 |
| rtl/uart_tx.v | 新增 | valid/ready 握手、8N1、连续发送、复位终止 |
| sim/tb/tb_packet_parser.v | 新增 | 包解析与错误恢复独立自检 |
| sim/tb/tb_uart_tx.v | 新增 | 双参数 TX 的独立周期参考模型 |
| sim/tb/tb_uart_packet_link.v | 新增 | 三模块纯仿真链路 |
| sim/run_stage2.ps1 | 新增 | 测试选择、双仿真器调度与当前结果检查 |
| sim/modelsim/run_stage2.do | 新增 | ModelSim 批处理入口 |
| sim/xsim/run_stage2.tcl | 新增 | XSim 运行、波形和完成检查 |
| docs/stage2_design.md | 新增 | 设计、接口、精确周期及协议约定 |
| docs/stage2_test_guide.md | 新增 | 中文复现命令、GUI 步骤与观察信号 |
| report/stage2_validation.md | 新增 | 实际结果、边界与本清单 |
| AGENTS.md | 修改 | 将协议状态更新为第二阶段实现约定，保留变更审批要求 |
| README.md | 修改 | 第二阶段导航与入口 |
| docs/project_context.md | 修改 | 明确现有布局及当前超时、恢复、序号语义 |
| docs/next_task.md | 修改 | 记录第三阶段入口及继续暂缓上板 |
| report/ai_devlog.md | 修改 | 本轮授权、设计选择、失败纠正及实际证据 |

文件与注释使用中文。PowerShell 入口为带 BOM 的 UTF-8，已实际通过 Windows PowerShell 的 `-File` 方式启动。

## 源码哈希与第一阶段保护

```text
rtl/packet_parser.v
D56E96D05F2207C83FEA175D991D6243CF9F324C81C468876726CA3A20D3BB84
rtl/uart_tx.v
F922500776879394F7C78092437AC3E1193D5DE2EAC443F74B223087FC40D596
sim/tb/tb_packet_parser.v
3A541824DE57DF4734E131F7098E5E990CCB753C960D3DF7AC0E8ADD5ADF151B
sim/tb/tb_uart_tx.v
46BC07BA130225A3ACC7FA9ADFB974BB04555999E89E72A57E68BDC80E8EB753
sim/tb/tb_uart_packet_link.v
22884E367C61CEC4EE4443664C5B809B931F6B24DFEE71115A41D17A19545CA4
```

第一阶段 RX 和 TB 的哈希与本轮开始时一致：

```text
rtl/uart_rx.v
4B61664EBEA1E0AF3F802355C77561BBECCDFB80E59C2F96AC471277B7C5DFDC
sim/tb/tb_uart_rx.v
CD71CBF4627F64C40939923276AC2A42C77565D585E8FFE822D5E9F730BC2A3F
```

本轮未重新运行第一阶段独立 TB；原 RX 参与了本阶段链路测试。`git diff --check` 通过，新增文件空白、中文说明性注释、UTF-8 和脚本语法也已检查。
