# 下一轮：同步保存ILA窗口和UART输入

日期：2026-11-01。B07已由filter_test_3通过，本轮目标是B08的内部窗口数值对照。保持当前STM32校准程序和FPGA算法，使用既有配对的 `build/release/v1.0-rc1/fpga/debug/system.bit` 与 `system.ltx`，不修改代码或重新综合。

## 要保存什么

建立两个独立记录目录：

```text
report/evidence/fixed_filter_ila_20261101/filter_test_4/static/
report/evidence/fixed_filter_ila_20261101/filter_test_4/motion/
```

每个目录保存同一次运行的DL16 `.atkdl`、D0 UART CSV、D1 UART CSV、I2C CSV，以及ILA的 `.ila`、CSV和截图。静止与运动分别独立开始，便于按窗口ID定位128个输入样本；每份开始前重配同版FPGA。两种记录各只需要一次ILA触发，普通Run Trigger即可。

## ILA设置

1. Hardware Manager打开当前 `hw_ila_1`，核对对应stage7_ila及完整探针。
2. Trigger Setup保留 `debug_feature_valid_o == 1`。深度1024、触发位置512，使用普通连续采样，无条件保存。
3. Capture Setup不设置仅feature_valid有效时保存的条件。1024个PL周期约20.48µs，可保存一次窗口发布的前后状态；不是1024个特征窗口。
4. MS/RMS/peak显示为无符号十进制。保留完整21组探针，包含窗口ID、首末SEQ、三轴特征、质量/报警和诊断计数。
5. 完成一份后先导出，再进行下一次触发，防止采样缓冲被覆盖。上传/保存本身不重新运行采样。

## 第一份：静止窗口

1. 按住STM32复位，模块保持固定。
2. 使用同版debug bit/ltx重新配置FPGA。配置结束后重新核对ILA触发设置。
3. 点击普通Run Trigger，让ILA等待feature_valid事件。
4. DL16使用此前有效的20秒、20MS/s、四路设置，开始立即采集，然后松开STM32复位。这样可捕获初始化、SEQ=0首包及首个有效窗口。
5. 模块保持静止至DL16记录结束；ILA应在首个有效窗口后完成，随后可保持Idle。
6. 将DL16归档及三路协议CSV保存到static目录，按下节命令保存ILA数据与截图。采完后不要再次复位或重新运行ILA，直到本份导出完成。

预期首个发布窗口ID=0，SEQ从3E到BD，共128个样本。静止真实传感器的MS/RMS/峰值通常非零，不要求和FixedSource一样全零。quality_valid及alarm_valid应有效，报警位结合实际MS与历史策略核对。

## 第二份：移动窗口

1. 再按住STM32复位，重新配置同版debug FPGA，核对触发设置；此时先不点击Run Trigger。
2. DL16开始新的20秒立即采集，再松开STM32复位。
3. 先静止约3秒，然后缓慢、持续移动模块；固定探头和线缆，避免碰触探测连接。
4. 已开始移动后，点击普通Run Trigger，继续运动直到ILA采样完成。保持本次DL16记录连续，直至采集结束。
5. 将该次DL16归档及三路CSV保存到motion目录；保存本次ILA数据和截图。导出前不要再次运行ILA。

重配FPGA使ID从0开始，DL16又包含本次首包，因此可从D0重建每个128点窗口，再按ILA发布的window_id和SEQ核对MS/RMS/峰值。ILA与DL16不要求共享触发线，但必须来自这同一次、期间没有遗漏的运行。

## ILA数据导出

以下命令已查阅本机Vivado2020.2命令手册，尚未在本轮连接硬件执行。待ILA采样完成，在Vivado底部 **Tcl Console** 中执行；不是PowerShell。

静止记录：

```tcl
set out_dir {D:/Code/zynq_vibration_monitor/report/evidence/fixed_filter_ila_20261101/filter_test_4/static}
file mkdir $out_dir
set ila_core [get_hw_ilas hw_ila_1]
set ila_data [upload_hw_ila_data $ila_core]
write_hw_ila_data "$out_dir/ila.ila" $ila_data
write_hw_ila_data -csv_file "$out_dir/ila.csv" $ila_data
```

运动记录执行相同命令，但把第一行目录末尾的 `static` 改为 `motion`。当前硬件截图对象名为hw_ila_1；若重新连接后名称不同，以Hardware窗口实际对象名替换该行。命令没有使用-force，遇到同名已有文件应换新目录或文件名，保留此前证据。

截图需保留触发标记、窗口ID、SEQ、三轴MS/RMS/peak、有效标志和诊断计数。CSV与原始.ila为本次主要分析数据，截图用于界面核对。

本机依据：`D:/Xilinx/Vivado/2020.2/doc/eng/man/write_hw_ila_data`、`upload_hw_ila_data`、`get_hw_ilas`。手册明确upload返回对应数据对象、write支持原始ILA与CSV；再次上传同一ILA会覆盖其内存对象，因此每份完成后立即写盘。

## 如何判定及之后的顺序

本轮主要检查128点输入的均方值、整数RMS和绝对峰值是否与内部ILA一致，SEQ/窗口ID是否连贯、有效状态是否正确。缓慢移动可能达不到2000计数且连续两窗的报警置位要求，不以没有报警判失败，不改变现有阈值。

本轮通过后继续B10中断/恢复的同步观察和三轮整机冷启动；B09受控数字频率及报警按既有设备条件执行。约3ms短间隔仍是独立待定位项，不能由本轮窗口数值通过撤销。所有文件均只保存既有配置产生的新证据，不修改Vivado工程、缓存或板卡下载设置。
