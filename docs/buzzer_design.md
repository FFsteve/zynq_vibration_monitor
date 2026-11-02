# 板载蜂鸣器报警扩展

日期：2026-11-01。用户请求在保持既有模块功能的基础上，让报警时板载蜂鸣器发声。本扩展为独立输出支路，一个输出寄存器，沿用已有报警规则，不新增复杂算法、分频时钟或状态机。当前新文件为独立变体，实际验证结果见后续 `../report/buzzer_validation_20261101.md`。

最新结果：独立仿真与实现实际通过，新配对文件在 `build/buzzer_release/debug/`，详细命令、资源、时序、警告及指纹见 [验证报告](../report/buzzer_validation_20261101.md)。用户下载后只需一次响停确认，当前尚未实测声音。

## 已核对的硬件

已阅读project_context、hardware_pinmap及实际原理图，并将底板第1/5页、核心板第3/7/12页渲染后逐页查看。

| 内容 | 图纸依据 |
|---|---|
| BEEP控制端 | 底板V3.9第5页：BEEP接J2.60，标注M14/B35_L23_P |
| 核心板连接 | 核心板2v5第12页：X3.60为B35_L23_P；第3页：该网络接U1G的IO_L23P_T3_35/M14 |
| 驱动与极性 | 底板第1页：BEEP经R7=1kΩ到Q1/S8050基极，R9=10kΩ基极下拉、R109=4.7kΩ输入下拉；发声器一端+3.3V，另一端接Q1集电极，发射极接地。高电平导通，低电平关闭 |
| Bank电压 | 核心板第7页：Bank35按R216/R219=0R、R218/R215=NC连+3.3V；新约束使用LVCMOS33。实物电压与装配本轮未测 |

实际PDF为 `docs/hardware/zynq_baseboard_v3_9.pdf` 与 `zynq_core_2v5.pdf`。图纸器件符号仅标BEEP，未列具体蜂鸣器料号；另外核对厂家 [领航者ZYNQ硬件资源说明3.2.3](https://www.openedv.com/thread-331198-1-1.html)，确认该板使用有源蜂鸣器，高电平驱动即可发声。最初尝试读取旧G盘规格书路径时文件已不可用，因此未把该文件当作本轮已读依据。

蜂鸣器及驱动已在板上，使用原PCB连接，不新增外部杜邦线，也不改变既有UART接线。最终发声仍需用户在实物确认，图纸检查不代替试听。

## 接口、寄存器和周期

模块 `alarm_buzzer`：输入clk、同步高有效rst、quality_valid_i、alarm_valid_i及三位alarm_axes_i；输出beep_o。

```text
蜂鸣器使能 = 非复位 AND 数据质量有效 AND 报警状态有效 AND 任一轴报警
```

只用一个beep_o寄存器，无独立状态机、计数器、分频器、PWM、存储器或反压。每个PL时钟上升沿采样上述条件；输出到高后持续发声，条件变假后下一个沿输出低。50MHz下最多一个时钟周期20ns的控制延迟，另有实际器件声学响应时间，未测。

不依赖feature_valid脉冲门控：报警状态在两个窗口之间保持时蜂鸣器也应保持发声。复位、断流或质量失效时关闭，不把旧报警状态造成的声音保留。板载有源蜂鸣器自行产生声频，不额外生成音频方波。

## 与现有模块的关系

- `rtl/alarm_buzzer.v` 为新增输出模块。
- `rtl/system_buzzer_top.v` 保留system_top的参数、核心例化和427位调试快照结构，只增加蜂鸣器例化和beep输出。默认filtered模式，当前独立构建也明确RETURN_FILTERED=1。
- 原 `rtl/system_top.v`、system_monitor_core及下级全部算法/通信模块不修改；新顶层直接使用同一份system_monitor_core。
- `constr/buzzer.xdc` 仅增加M14输出约束及蜂鸣器外部非同步输出例外；beep寄存器的内部输入路径仍正常计时。
- `scripts/build_buzzer.ps1/.tcl` 只在 `build/buzzer_release/debug/` 构建新变体，保留配对ILA。原build_release脚本、冻结rc1和本地Vivado工程不改。
- 不更改STM32、十字节协议、报警门限、采样率或窗口长度。该模块只观察状态，不反馈至原链路；额外物理扇出和布局变化仍由新构建时序检查确认。

## 本次验收范围

1. 新模块自检：三轴/组合、无报警、报警/质量无效、报警中失效、恢复和复位优先。
2. 新顶层自检：与原system_top接受同一串口激励，逐拍比较UART TX及全部427位快照；正常运动置位、正常解除、坏校验、静默失效及恢复均覆盖。
3. 新变体独立综合/实现、引脚/时钟、资源、内部时序、DRC与CDC检查，生成新配对bit/ltx。不重复整项目无关测试。
4. 用户上板只需静止不响、运动报警响、放稳解除后停止三个现象，顺带确认原UART和ILA仍工作；软件检查不能先填成实物发声通过。

Verilog自检命令为 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File sim/run_buzzer.ps1`；独立构建命令为 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build_buzzer.ps1`。
