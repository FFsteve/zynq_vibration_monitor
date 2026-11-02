# 一次完整比赛演练

日期：2026-11-01。目标是从启动到静止、运动报警、恢复正常完成一次可重复演示，约3～5分钟。沿用已验证代码，不重新综合。本轮只需三张关键状态截图或一段视频，不要求新DL16长记录、协议CSV、原始ILA或边沿捕获；已有filter_test_3/4用于说明精确数值正确性。

## 演练前准备

1. 保持已使用的接线，固定探头和线缆，模块初始放稳，便于之后移动。
2. 打开Vivado Hardware Manager。FPGA使用这一对文件：

```text
D:/Code/zynq_vibration_monitor/build/release/v1.0-rc1/fpga/debug/system.bit
D:/Code/zynq_vibration_monitor/build/release/v1.0-rc1/fpga/debug/system.ltx
```

3. STM32使用已烧录、已验证的SensorCalibratedTrial新校准程序。正常情况下保留Flash程序，上电运行即可；如确需重新下载，已验证版本副本是：

```text
D:/Code/zynq_vibration_monitor/build/stm32_calibration_versions/sixface_r1_20261101_validated/vibration_monitor.hex
```

4. ILA打开hw_ila_1/stage7_ila，保留1024点、触发位置512、ALWAYS连续采样。显示RMS/峰值为无符号十进制，alarm_axes为三位二进制。
5. Trigger Setup使用四行，组合AND；前三行固定为debug_feature_valid_o=1、debug_quality_valid_o=1、debug_alarm_valid_o=1。第四行为debug_alarm_axes_o[2:0]，按下表修改。此次用普通数值比较，不使用RXX/FXX边沿模式。

| 演示阶段 | alarm_axes运算符 | Binary比较值 |
|---|---|---|
| 初始静止 | == | 000 |
| 运动报警 | != | 000 |
| 放稳恢复 | == | 000 |

## 第一步：从头启动

1. 让板卡重新上电。STM32保留已有校准程序。
2. 按住STM32复位，Program Device重新配置上述debug bit/ltx。
3. 核对ILA触发为初始静止条件，点击普通Run Trigger，然后松开STM32复位。
4. 模块保持静止，等待ILA完成采样。初始化加首次有效窗口一般需约1～2秒，操作耗时无需卡精确秒数。

FPGA采用当前JTAG配置方式，重新上电后要重新Program Device，这是现有演示流程的一部分。本轮不制作额外独立启动系统。

## 第二步：保存静止状态

采样完成后，将黄色光标移到触发点右侧，例如Sample=700附近；此时左侧Value列读取新发布窗口。ILA保存的是一次快照，不会因模块后续变化自动刷新。

应看到quality_valid=1、alarm_valid=1、alarm_axes=000，RMS处于较低水平。真实传感器静止RMS不要求为0，也不要求复现上次某个精确数值。window_id、SEQ和计数只作为状态辅助，本轮不要求重新逐窗精算。

保存截图 `01_static.png`。

## 第三步：运动并展示报警

1. 将第四行改为alarm_axes != 000，前三行保持为1且AND，点击Run Trigger。
2. 复现filter_test_4的运动，持续数秒，固定探头和线缆。慢慢换一个静态姿态未必产生足够能量，动作应有持续变化，但无需强求某个轴或固定频率。
3. 采样完成后即可放稳。将光标移到触发点右侧，观察报警位与有效标志。
4. 保存截图 `02_alarm.png`。

alarm_axes非零且quality_valid/alarm_valid为1表示有可信报警状态。001/010/100依次为X/Y/Z，多个轴可同时报警；上次主要出现100。本轮任一轴正常报警即可，不强求再次只Z报警。报警由连续两个高窗口确认；瞬时RMS或峰值大不等于立即报警，某个低窗口仍保留报警也可能是正常滞回。

如果一直等不到报警，保留本次实际现象，先复现上一轮动作；不要调整门限凑通过。可以使用已有filter_test_4数据辅助说明已观察到Z报警。

## 第四步：展示正常解除

1. 保持STM32与FPGA继续运行，模块放稳。
2. 将第四行改回alarm_axes == 000，前三行仍为1且AND，点击Run Trigger。
3. 放稳并等待约3秒，满足连续两个低窗口后应完成捕获。
4. 将光标移到触发点右侧，确认alarm_axes=000，同时quality_valid=1、alarm_valid=1。
5. 保存截图 `03_recovered.png`。

运动结束至修改触发可能已经超过3秒；此时捕获当前正常状态也足够，不要求抓解除瞬间。恢复过程中保持程序运行，不按STM32复位或重配FPGA，以免把数据失效造成的清零当正常解除。若放稳约10秒仍无法捕获，不继续增加测试，记录此现象后针对解除问题排查。

## 最少保存内容与完成标准

建议目录：`D:/Code/zynq_vibration_monitor/report/evidence/competition_demo_20261101/`。保存三张截图，或用一段视频覆盖启动、运动和恢复。另用一两句话记录实际使用程序、启动是否成功、哪个轴报警及放稳后是否正常解除即可。

完成标准是一次按上述流程成功运行：有效静止状态、有效报警状态、有效恢复状态均能展示。已有精确滤波/窗口报告复用，不要求本轮再导出CSV证明一次相同的运算。

STM32复位恢复为可选附加动作：保存完正常解除截图后，按一次STM32复位，重新Run Trigger抓到quality_valid/alarm_valid恢复且有新窗口即可。无需三轮重复或额外故障注入。

## 可配合的简短讲解

- 静止时说明：传感器经校准后输入FPGA，FPGA去除重力与慢变化分量，再进行FIR与窗口统计。
- 运动时说明：三轴独立计算RMS和峰值，连续两个窗口达到演示门限才报警。
- 放稳后说明：采用不同置位/解除门限和两窗确认，减小状态反复跳变，恢复低振动后自动解除。
- 展示已有结果时说明：定点滤波和窗口数值已与参考精确对照，已有综合资源及时序报告；实际采样约250.5Hz，物理标准频响尚未验证。

本文件为演练指导，本轮未执行新硬件操作、仿真、编译或综合；后续根据实际截图/视频登记演练结果。
