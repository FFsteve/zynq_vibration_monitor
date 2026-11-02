# 六面验证参数固件更新与软件验证

日期：2026-11-01。用户明确要求根据此前测试更新参数，本轮将已经通过选定第二轮/针对性复测离线静态指标的第一轮固定参数用于独立校准工程。**参数已更新，软件检查和三个Keil目标重建通过，新AXF/HEX已生成，尚未烧录或板测。**

## 参数与作用范围

| 轴 | 零偏，计数 | 比例系数 | 零偏Q16 | 比例Q16 |
| --- | --- | --- | --- | --- |
| X | +727.653493 | 1.004642976 | 47687499 | 65840 |
| Y | −552.006188 | 0.994565297 | −36176278 | 65180 |
| Z | +5217.627726 | 0.978043625 | 341942451 | 64097 |

公式仍为 `round((raw-b)*k)`，采用原有64位中间量、对称舍入与signed16饱和，输出保持16384计数/g。Q16系数由第一轮精确有理数按最近整数、半值远离零生成，没有重拟合第二轮。

标识为 `sixface_r1_20261101_validated`。参数来源、第一轮24项输入指纹及独立验证指纹写入 `report/mpu6050_calibration_params_20261101.json`。第一轮输入集合指纹为 `de0ba0a3da42483f7220c3f6d7a648f1d3c3457aef4a689709ba393692ebd4c5`，参数头注释与之相同。

- 更新 `stm32/app/accel_calibration_params.h` 的系数、标识和来源说明。
- 更新 `stm32/test_calibration.ps1` 默认分析参数文件，使现有全输入C/Python检查使用当前系数；保持UTF-8 BOM。
- 原校正算法、采集调度、UART十字节布局及XOR不改；不修改RTL、约束、Keil工程或下载设置。
- `SensorSource`仍为原始计数，`FixedSource`仍为既有常量；只有独立工程中的 `SensorCalibratedTrial` 使用校准分支。字段语义沿用既有实验目标的校准计数，没有再改变协议。

## 版本保留

重建前已将旧参数头、旧实验AXF/HEX和构建日志复制到 `build/stm32_calibration_versions/trial_20261031_short_capture/`，不修改rc1及此前证据。当前构建目录仍为 `build/stm32/SensorCalibratedTrial/`；另复制本次AXF/HEX、参数头和参数来源JSON到：

```text
build/stm32_calibration_versions/sixface_r1_20261101_validated/
```

该目录HEX的SHA256为：

```text
895bbfa1f1076716d045b9235c65d62adbddf2c927687b5f0cc3e177c75a41d5
```

新HEX为4808数据字节，记录校验和、单一EOF、地址范围0x08000000～0x080012C7及64KiB Flash范围检查通过。不要使用旧短记录归档HEX冒充本次参数版本。

## 实际命令与结果

在项目根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/test_calibration.ps1 -Python 'C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/test_portable.ps1 -Python 'C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/build_keil.ps1 -Target both
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/build_keil.ps1 -Target SensorCalibratedTrial
```

| 本轮实际检查 | 结果 |
| --- | --- |
| 校准C正常/原位操作/非法指针/饱和/诊断复位 | 通过 |
| 初始化、未就绪、I2C失败和重试恢复、发送失败SEQ缺口 | 通过 |
| FixedSource绕过校准 | 通过 |
| 三轴各65536输入，共196608轴值 | 实际C输出与精确有理数定点参考完全一致，较理想校正最多差1计数 |
| 65536个实际C输出包 | 补码、SEQ、XOR、单调性及饱和位图核查通过 |
| 原可移植C及协议向量 | 65536编码值、32向量通过 |
| FixedSource、SensorSource、SensorCalibratedTrial Keil全量重建 | 三者均0错误、0警告 |
| 实际C函数对应六面30059原始样本 | 六面建议静态均值指标全部满足，0样本饱和 |
| 新HEX | 校验和、EOF和Flash范围通过 |

全输入边界扫描中，X/Y/Z各有879/373/4482个输入触发饱和，属于覆盖全部signed16输入的边界测试，不是实物采集中发生的饱和次数。真实选定六面样本经当前C函数校正均未饱和。

首次Keil构建在受限执行环境无法启动旧版ArmCC/ArmLink，直接版本检查显示Windows DLL重定位错误；没有改源码来掩盖该错误。切换执行环境后重跑两目标和独立校准目标成功，失败与成功日志均保留。没有把首次失败写成通过。

本轮C输出对六面记录的校核使用实际全范围C向量逐轴查表，不只是再次执行同一浮点公式。六面整数校正后的合成幅值均值约1.000524/1.001092/1.000792/1.000106/1.000729/0.999086g，依次为xp/xn/yp/yn/zp/zn，全部在建议范围。

证据位于 `report/evidence/calibration_firmware_20261101/validation.json`、C向量ZIP及原始/校准Keil与可移植测试日志。C全输入检查的计数和最大差异来自本轮实际工具输出，指纹对应的完整C向量已另存ZIP并通过CRC及解压SHA256核查。

## 下一步实际使用

打开 `stm32/keil/vibration_calibration.uvprojx`，目标选择 `SensorCalibratedTrial`；使用此前已验证的DAP方式下载本次AXF，或通过既有工具下载上述版本目录的HEX。本轮没有连接DAP或代为下载，不变更烧录设置。

下载后D0已经是校正计数，不可再当原始标定输入；FPGA raw回传的D1应与D0对应包一致。优先保存Z朝上/朝下等代表姿态的实际输出，核对接近正负1g、横轴残差、错误和SEQ，并记录新固件指纹。内部变量 `g_accel_calibration.last_raw/last_corrected/samples/clipped_samples` 可供调试，但停机观察会扰动时序。

原SensorSource继续用于需要未补偿数据的复查；filtered/debug回传仍按原约定乘4恢复尺度。周期性3ms间隔、之前静止瞬态、FIR/ILA/RMS/报警和完整冷启动分别验收，参数更新不自动修复或签收这些项目。

本轮未重跑ModelSim/XSim或Vivado，因为没有RTL/约束变更。统一第七阶段入口原先未包含校准专项，当前检查仍为单独执行，不声称统一入口已经覆盖新参数。本次只是新的校准固件检查点，不覆盖原rc1、不自动新冻结正式发布或提交/推送Git。
