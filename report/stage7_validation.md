# 第七阶段回归、冻结与交付记录

日期：2026-10-31。结论：**软件收尾、完整回归、最终源码构建和候选交付完成；新版整体实物验收尚未执行。** 候选版为v1.0-rc1，不以“最终阶段”名称冒充已经上板通过。

完整性核对见 [需求审计](requirements_audit.md)，操作入口见 [交付指南](../docs/stage7_delivery.md)，完整 [上板方案](../docs/board_test_plan.md) 包含B01～B12及判断标准，[实物记录表](final_board_record.md)仍保持未验证。源码/发布文件哈希由 [冻结清单](source_manifest.json) 和 [发布清单](release_manifest.json) 提供。

## 本次实际执行

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_stage7.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_release.ps1
python -X utf8 host/board_test.py generate --output build/stage7_board_vectors
python -X utf8 scripts/package_release.py --version v1.0-rc1
```

本机脚本使用已提供的Codex Python3.12运行时、NumPy2.3.5、ModelSim SE64 2020.4、Vivado/XSim2020.2和Keil ARM5.06 update7。工具在已授权的正常进程环境执行；全量回归最终日志 `build/stage7_regression_final.log`，发布构建最终日志 `build/stage7_release_final.log`。

回归一键入口最终10步骤全部正常退出，结果为 `PASS_STAGE7_REGRESSION`。每次阶段脚本仍先将当前结果标记NOT_RUN；没有跳过失败或借用旧PASS。机器明细见 [验证摘要](stage7_validation.json)。

## 全部RTL和应用回归

项目有18个RTL模块、19个独立自检顶层（额外一个UART链路自检）。每个仿真器执行21项阶段测试，包含第六阶段对旧队列/解析器的两项重复针对性回归；两套工具共42次，19个不同TB均实际覆盖。

| 阶段 | 本轮实际结果，ModelSim与XSim一致 |
|---|---|
| 一 | UART RX：1398字节、8个预期停止位错误事件，errors=0 |
| 二 | parser=171、TX=2931922、UART链路=14项检查，errors=0 |
| 三 | 上电复位=124、队列=78、通信核心=255、旧top=272，errors=0 |
| 四 | DC=98192、FIR=8222769、三轴滤波=1604429、UART滤波集成=2490721，errors=0 |
| 五 | 开方=231556、窗口=131447、报警=10365、特征集成=94715，errors=0 |
| 六 | 选择器=786437、完整系统=561050、新top=277，旧队列/解析器=78/171，errors=0 |

另有每工具12项非法配置/缺失系数测试，合计24次主动拒绝；独立Python逐样本、窗口、线缆与时序导出检查全部通过。原始/滤波完整链路各5632包和40窗，包含3轴隔离、九处截断、坏校验/停止位、缺口/断流、拥塞/满队列、复位取消全部历史和默认50MHz/115200通道，覆盖先前失败相关边界。

主机单元测试11项通过，其中4项新回放器测试验证短写、不突发补发、零写中止和打开硬件前保护旧记录；均使用假设备，没有打开真实COM。单元日志中的预期 `FAIL capture` 是负向CLI测试，本次unittest总体OK、退出码0，不把它当作实际串口失败或忽略真实非零退出。

可移植C检查通过：65536个带符号组包值、32组C/Python向量相同。Keil两个目标全量重建均0错误/0警告：FixedSource Code4408/RO280/RW60/ZI1060，SensorSource Code3856/RO280/RW60/ZI1060。最终AXF转HEX后分别4748/4196有效数据字节，Intel HEX校验、EOF和0x08000000～0x0800FFFF范围检查通过；没有改Keil下载设置。

## 最终三种下载版

直接从同一最终功能源码独立综合、优化、布局、布线、检查并生成比特流，不是把历史DCP改名。原始/滤波版和第六阶段功能一致；debug版只由Tcl插入ILA，不修改功能RTL、输入协议或引脚。

| 变体 | LUT | FF | DSP | BRAM | 50MHz建立裕量 | 保持裕量 |
|---|---:|---:|---:|---:|---:|---:|
| raw | 3401 | 6101 | 6 | 0 | 5.205ns | 0.037ns |
| filtered | 3324 | 6091 | 6 | 0 | 8.300ns | 0.028ns |
| debug | 6695 | 11520 | 6 | 12 | 5.432ns | 0.014ns |

三版均0无时钟寄存器、0未约束内部端点，DRC无Error/Critical Warning，write_bitstream实际成功。各版8项DRC Warning：3DPOP-1、3DPOP-2、1RTSTAT-10、1ZPS7-1；没有降级或屏蔽。普通版无路由负载为保留快照输出，debug版剩余25条此类网络属于调试核内部未使用支路，不再把它们写成427个未连接探针。

普通版CDC为1项CDC-3 Info；debug版为10项CDC-3 Info和2项CDC-9 Info，新增部分来自调试hub的JTAG时钟域；原UART两级同步链仍受检查，第一级D之外没有自定义整链false_path。异步UART的输入/输出延迟提示如实保留，不虚构外部同步时钟。

ILA采用21组、总427位现有调试快照，1024点深度，时钟为缓冲后的PL50MHz，probe_map与ltx实际对应，ltx声明50000000Hz。bit和ltx来自同一debug实现；只有工具生成/实现通过，尚未在板上发现ILA或完成触发采集。1024连续点只有20.48us，文档不将其当作长时间窗口波形。

## 修复和复现证据

- host/requirements.txt补充实际数值工具需要的NumPy，原先只有在线串口依赖声明；本轮没有在全局Python安装项目包。
- 一键回归初次在unittest处被PowerShell5.1的stderr/Stop行为中止，修复为正常收集stderr并以进程退出码评分；随后从全部阶段起重新运行，最终10步骤全通过。首次日志单独保留，不记为通过。
- ILA开启采集条件时，Vivado2020.2拒绝比较单元数量1，明确要求2～16。改为2后重新完整构建三版，debug的生成、实现和bit/ltx均成功；未改功能RTL。
- 技能官方验证器最初缺PyYAML，本轮仅在build/stage7_tools安装PyYAML6.0.3，实际运行quick_validate通过。技能并未安装到全局目录；没有声称独立代理行为评测。
- 普通受限环境的临时目录清理曾影响单元测试，最终全量流程与11项自检在正常执行环境通过；没有改系统安全设置来掩盖设计错误。

第六阶段曾失败的原始模式计算分支保留检查、本轮再次在所有变体验证；三轴FIR、三个开方器、报警均存在，只有一个实际外部UART发送器。前五/六阶段功能源码保持原验收版本，重要纠错记录在AI开发日志。

## 候选冻结和交付边界

交付目录为 `build/release/v1.0-rc1/`，包含三版FPGA、两个STM32目标、10组受控数字fixtures、回归/量化证据、自有源码ZIP及清单。源码ZIP实际CRC与逐文件SHA256核对，不包含厂商Libraries/PDF或生成IP源码；本地重新编译STM32仍需已有Libraries。发布打包器拒绝覆盖已冻结同版本。

项目技能入口为 [fir-validation](../skill/fir-validation/SKILL.md)，已将早期英文占位说明替换为实际流程。Markdown/说明性注释为中文，文件路径ASCII，PowerShell含中文文件为UTF-8 BOM；链接和空白检查按最终文件执行。

**完整性结论：已知软件要求满足并形成可下载/可观测的候选交付；不能断言整个实物项目全部通过。** 传感器初始化实测、校准、真实采样、板上新滤波/窗口/报警、JTAG调试识别和三轮冷启动须按B01～B12执行。缺少正式竞赛规则全文时，也不能保证未知评分与提交条款合规。

本轮没有接线、测量、复位、编程硬件、制作非易失FPGA启动系统或推送仓库。实物失败需形成新候选版本和新哈希，而非修改冻结版后继续引用本次证据。
