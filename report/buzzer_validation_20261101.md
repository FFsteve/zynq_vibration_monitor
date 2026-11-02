# 板载蜂鸣器扩展实现与验证

> 2026-11-02 状态更新：用户已确认最后一次上板完成、蜂鸣器正常响应。下文保留 2026-11-01 构建与仿真时点的原始记录；当前交付与下载入口见 [current_release.md](current_release.md)。

日期：2026-11-01。用户要求在现有比赛原型基础上增加报警发声。新增独立alarm_buzzer及system_buzzer_top，不修改18份既有RTL、原三端口system_top、STM32、协议或报警门限。

当前状态：ModelSim/XSim自检、新旧顶层对照、独立Vivado综合/布局布线/时序检查及新bit/ltx生成均实际通过；实际板上声音未验证。可供人工下载的新文件为 `build/buzzer_release/debug/system.bit` 与同目录 `system.ltx`，STM32保持当前已验证校准程序。

## 功能与硬件依据

蜂鸣器控制条件为 `!rst && quality_valid && alarm_valid && (|alarm_axes)`，一个输出寄存器，每个PL时钟更新，50MHz下最多增加一拍20ns的控制延迟。报警持续时输出持续高电平；解除、质量失效、报警失效或复位后输出低。

实际查看底板V3.9第1/5页与核心板2v5第3/7/12页，核对BEEP经S8050驱动、M14/Bank35及图面3.3V供电；厂商硬件资源说明确认有源蜂鸣器。图纸与来源见 [设计说明](../docs/buzzer_design.md)。实际装配、电压和声学响应本轮未测。此前旧G盘规格书路径已不可用，没有把它写成本轮已读文件。

新增约束为beep/M14/LVCMOS33、DRIVE8、SLOW，仅在独立蜂鸣器构建中读取。原constr/top.xdc及system_uart_rx_cdc.xdc未被本轮修改，用户先前的手动修改保留。原冻结rc1不覆盖，新目录为build/buzzer_release/debug。

## 实际运行的自检

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File sim/run_buzzer.ps1
```

| 工具 | 用例 | 实际结果 |
|---|---|---|
| ModelSim2020.4 | alarm_buzzer | PASS，42检查，0错误 |
| ModelSim2020.4 | system_buzzer_top | PASS，12732334检查，0错误 |
| XSim2020.2 | alarm_buzzer | PASS，42检查，0错误 |
| XSim2020.2 | system_buzzer_top | PASS，12732334检查，0错误 |

模块用例覆盖所有报警掩码及质量/报警有效组合，报警中失效、恢复、解除和复位优先。新顶层用例向原system_top和新增顶层施加同一UART输入，逐拍比较UART TX及427位调试快照；1056合法包与1个坏校验包覆盖正常报警/解除、错误包拒收、静默失效及重新建窗。

顶层对照使用1MHz/100000baud压缩参数、4ms包间隔和12ms断流门限；不是新板50MHz的实时串口采样。模块寄存器自检使用50MHz时钟。默认50MHz新板版本另由独立构建确认时序，最终实物响停仍待用户验证。

核对18份既有RTL的SHA256均与冻结rc1源码清单相同。新顶层与旧顶层的文本差异经归一化检查，仅为模块名、filtered默认值、beep端口及蜂鸣器例化，未改原计算和调试快照内容。这些检查支持对照场景下原链路行为一致，不冒称所有实物干扰已经测量。

第一次ModelSim在受限运行环境出现DLL重定位问题，换正常执行环境后可运行；初次编译新测试台时超时常量超过默认32位，已改为显式64位并重跑，四项最终全部通过。失败日志保留于build/buzzer_sim_environment_failure.log及buzzer_sim_compile_failure.log，最终日志为build/buzzer_sim_run.log。

## 独立构建

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build_buzzer.ps1
```

构建只使用新system_buzzer_top，RETURN_FILTERED=1，保留21组427位ILA，端口clk/U18、pl_rx/K14、pl_tx/M15、beep/M14。生成新debug bit/ltx并检查引脚、时钟、计算支路、唯一UART发送器、内部建立/保持、DRC和CDC。内部beep寄存器输入路径参与正常时序检查；蜂鸣器端口为无外部同步采样时钟的执行器，不伪造外部同步输出预算。

实际构建退出0，结果为 `PASS buzzer_release variant=debug mode=1 setup_slack=7.377 hold_slack=0.020`。

| 项目 | 实际结果 |
|---|---|
| 内部建立/保持裕量 | 7.377ns / 0.020ns，均满足 |
| 无时钟寄存器 / 未约束内部端点 | 0 / 0 |
| LUT / 寄存器 | 6625 / 11521 |
| DSP / 36Kb BRAM等效数量 | 6 / 12，与原debug版相同 |
| 相比原debug版寄存器数量 | 增加1，11520→11521 |
| BEEP实际实现引脚 | M14、Bank35、LVCMOS33、DRIVE8、SLOW |
| ILA | 原21组、427位保留，实际产生配套ltx |
| DRC | 0错误、0严重警告，8项Warning保留 |
| CDC | CDC-3共10项Info、CDC-9共2项Info，无报告Warning/Critical |

DRC的8项为DPOP-1三项、DPOP-2三项、RTSTAT-10一项、ZPS7-1一项，与原报告的类别/数量相同；未屏蔽规则或引入PS。整个构建日志汇总45条Warning消息，包含多阶段重复及工具提示，不能将8项DRC误写成整个流程只有8条警告。内部端点参与正常时序，外部蜂鸣器及UART TX的同步接收预算不作虚构。

原debug版LUT6695、新版6625是整体优化/映射结果变化，不将减少70个LUT解释成蜂鸣器有负资源开销。原18份RTL哈希不变及仿真对照证明本轮比较范围下的原链路行为一致。

首次在受限环境运行Vivado启动脚本时无法进入安装目录，换正常执行环境重试；初次日志保留build/buzzer_build_environment_failure.log，最终日志为build/buzzer_build_run.log。构建输出、引脚及旧冻结文件指纹的实际检查返回 `PASS new_buzzer_artifacts_and_unchanged_old_fpga_files`。

新system.bit的SHA256为 `2631a9d1d3e89ccb0ec4de3fe9626d780cc754945f69c6f3dffbdafb57ee7b4b`；system.ltx为 `0d8a495be673a0d07fd5c42eec5ce3d174492d0eeb98affd398f3ce2ebf9efbb`。完整机器结果见 `evidence/buzzer_20261101/build.json`，同时存于 `build/buzzer_release/build_manifest.json`。

本次ltx内容与原debug版相同，因为探针及ILA配置没有变化；仍建议下载时从新目录成对选取，避免与其他变体混淆。旧rc1的raw/filtered/debug三个bit和debug ltx共四个文件，均与旧发布清单SHA256一致，没有覆盖。

## 文件与后续

新增rtl/alarm_buzzer.v、rtl/system_buzzer_top.v、constr/buzzer.xdc、两个对应TB、独立仿真/构建脚本及设计说明。软件检查与实际源文件指纹在 `evidence/buzzer_20261101/software_checks.json`。旧构建脚本、旧bit/ltx、原Vivado工程/缓存、STM32和下载设置均不改。

拿到本轮配对新bit/ltx后，保持当前校准STM32程序，用户仅需一次上板确认：静止不响，任一轴有效报警时响，放稳正常解除后停止；可顺带看原UART/ILA继续更新。无需重复六面、全部频点或整项目板测。本轮没有操作板卡或改变烧录设置，不能先将“生成了bit”写成“蜂鸣器板测通过”。
