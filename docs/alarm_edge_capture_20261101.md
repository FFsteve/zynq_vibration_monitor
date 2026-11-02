# 下一轮：Z轴报警置位与正常解除边沿

日期：2026-11-01。filter_test_4已完成窗口数值核查，并观察到Z报警及第一个低窗口保持。本轮仅补直接置位/解除边沿，沿用当前STM32校准程序及配对debug bit/ltx，不改RTL、阈值或协议，不重新综合。

## 记录目录

```text
D:/Code/zynq_vibration_monitor/report/evidence/fixed_filter_ila_20261101/filter_test_5/alarm_assert/
D:/Code/zynq_vibration_monitor/report/evidence/fixed_filter_ila_20261101/filter_test_5/alarm_release/
```

每份保存同一次运行的20秒DL16归档、D0 UART CSV、D1 UART CSV、I2C CSV，以及原始ILA、ILA CSV和截图。每份开始时先按住STM32复位，再Program Device下载同版debug FPGA；保持STM32复位直到DL16采集开始，防止记录前已有未采到的输入。

## ILA共同设置

使用hw_ila_1/stage7_ila。深度1024，触发位置512，Capture mode为ALWAYS，普通Run Trigger。

Trigger Setup使用四行条件，组合选AND或All probes，必须同时满足。清除其他遗留比较条件。各行均使用等于运算，alarm_axes的Radix须选Binary。

| 探针 | 置位记录 | 解除记录 |
|---|---|---|
| debug_alarm_axes_o[2:0] | RXX | FXX |
| debug_feature_valid_o | 1 | 1 |
| debug_quality_valid_o | 1 | 1 |
| debug_alarm_valid_o | 1 | 1 |

alarm_axes从左到右是Z、Y、X。R代表该位0到1，F代表1到0，X是不限制该位；输入RXX/FXX三个字符，不输入引号或位宽前缀。左端的字母作用于Z轴。其他轴是否报警不影响Z边沿匹配。

R/F的含义及Binary比较格式已查阅 [AMD UG908触发比较值说明](https://docs.amd.com/r/2021.2-English/ug908-vivado-programming-debugging/ILA-Probe-Compare-Value-Settings)。本机Vivado2020.2的run_hw_ila帮助确认基本触发支持AND以及ALWAYS连续捕获。本轮未连接硬件执行触发；若本机界面拒绝输入R/F，保留实际提示再定位，不把它换成普通数值后仍称边沿触发。

## 第一份：报警置位

1. 按住STM32复位，Program Device重新下载当前同版debug bit和ltx。
2. 核对上述设置，alarm_axes比较值用RXX，点击普通Run Trigger，让ILA等待Z上升沿。
3. DL16开始新的20秒立即采集，然后松开STM32复位。
4. 静止约3秒，随后复现上一轮能使Z报警的运动，持续数秒。固定探头与线缆，使连接不随板卡运动拉扯。
5. ILA触发后停止运动，模块放稳，继续记录至20秒结束。
6. 保存整次DL16及三个协议CSV，再导出ILA原始数据和截图，存入alarm_assert。

应直接看到Z报警位0到1，quality_valid和alarm_valid保持1。只有Z报警时总线为000到100。默认需要连续两个窗口MS达到2000平方；使用完整输入参考检查两窗确认，20.48µs的ILA缓冲本身不足以覆盖两窗。

## 第二份：正常解除

1. 另起一轮，按住STM32复位并重新Program Device同版debug FPGA。
2. alarm_axes比较值改为FXX，其他三行均为1且AND，点击普通Run Trigger。
3. DL16开始新的20秒立即采集，再松开STM32复位。
4. 先静止约3秒，再复现能够使Z报警的运动，持续约4～6秒，然后停止并放稳，保持到记录结束。FXX从一开始等待，不需要人在报警后的短时间内切换触发。
5. 若Z实际曾置位且随后连续两个窗口MS不高于1500平方，ILA应抓到正常下降沿。
6. 保存全部本轮文件到alarm_release。

应看到Z报警位1到0，quality_valid和alarm_valid保持1。若只有Z报警，总线为100到000；若其他轴也报警，只要求Z位下降并结合各轴状态解释。

本轮解除过程中保持STM32运行，不按复位、不重配FPGA。复位或断流会使质量/报警有效标志失效，状态清零属于数据失效，不等于正常解除。四行AND中的有效条件用于排除这种情况。

若DL16的20秒已经结束而ILA仍未触发，应停止这次ILA等待，原样保存并注明未触发，下一次使用新目录；不要在DL16结束后继续运动补触发，再冒充同次对应记录。触发是否成功取决于实际窗口能量，不保证手动动作每次都达到门限，不调整门限凑通过。

## ILA导出命令

ILA采样完成后，在Vivado底部Tcl Console执行；不是PowerShell。

```tcl
set out_dir {D:/Code/zynq_vibration_monitor/report/evidence/fixed_filter_ila_20261101/filter_test_5/alarm_assert}
file mkdir $out_dir
set ila_core [get_hw_ilas hw_ila_1]
set ila_data [upload_hw_ila_data $ila_core]
write_hw_ila_data "$out_dir/ila.ila" $ila_data
write_hw_ila_data -csv_file "$out_dir/ila.csv" $ila_data
```

解除记录将第一行末尾alarm_assert改为alarm_release。每份导出完成后再重新运行ILA；未使用-force，保留既有文件。截图尽量显示报警变化前后、触发标记、三轴MS/RMS/峰值、window_id、SEQ和有效标志。

## 这两份之后

按输入参考核验置位的两个高窗口、解除的两个低窗口，以及ILA实测边沿和有效状态。之后做B10同步中断/恢复和三轮整机冷启动；B09受控数字频率独立按设备条件执行。3ms短采样间隔继续单列定位，不因报警通过就撤销。

本文件是操作方案，不是本轮已执行的板测结果。没有改动功能代码、约束、下载设置或原始数据，也未连接硬件、重新仿真或构建。
