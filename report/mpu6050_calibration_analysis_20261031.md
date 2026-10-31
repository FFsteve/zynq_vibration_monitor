# MPU6050 六面短记录分析与实验修正

日期：2026-10-31。结论：73个完整包的数据内容和本次校正软件检查通过；已生成独立实验校准固件，但正式传感器校准尚未通过。`formal_calibration_pass=false`，不能把同一批记录校正后主轴恰为正负1g当作独立验证。

## 实际输入与质量

本次读取 `report/evidence/` 下的 `xp_r1`、`xn_r1`、`yp_r1`、`yn_r1` 四对 `.atkdl`/UART CSV，加上第三阶段的 `sensor_source_20261030.atkdl`、`sensor_zdown_20261030.atkdl` 及对应D0 CSV。原文件未修改；六个归档均通过ZIP CRC，原文件SHA256见配套JSON。用户确认MPU6050相同，旧Z来自第三阶段；跨阶段实际固件/配置一致性仍未取得实物回读证据。

四份新归档的实际设置均为20 MS/s、50 ms，阈值1.5V，四通道；并非计划的20秒。旧Z也为50 ms。解码器配置保留在JSON中。本次按D0导出约定分析TX数据：完整包逐字节起止位齐全、每字节8位记录与十六进制值一致，独立流式解码结果一致，XOR正确、完整包之间无序号缺口或重复。未观察到原始XYZ数值到达有符号16位端点。

| 姿态 | 完整包数 | X均值 | Y均值 | Z均值 |
| --- | --- | --- | --- | --- |
| X正向上 | 13 | 16964.154 | 513.231 | 6381.846 |
| X正向下 | 12 | -15555.833 | -452.000 | 6490.667 |
| Y正向上 | 12 | 443.000 | 15938.667 | 5248.333 |
| Y正向下 | 12 | 869.167 | -17009.333 | 5640.500 |
| Z正向上，旧记录 | 12 | 549.500 | -289.167 | 21952.667 |
| Z正向下，旧记录 | 12 | 2939.000 | -902.000 | -11375.833 |

完整包内未发现UART警告；首尾片段仍保留：yp有6个未组成完整包的已解码字节，yn有4个，旧zp有3个；xn末尾还有不完整字节的数据位。它们不算完整样本，也不按内部丢包隐藏处理。原D1边界警告不因本次只分析D0而被撤销。

采样周期仍有问题：xn有一次3.00345 ms，旧zp有一次2.99475 ms的包起点间隔，其他所示间隔主要在约3.993～4.002 ms。原因未定位，本次校准未修改调度或传感器配置，不能宣称严格250Hz实测已经通过。短记录的均值估计与动态频率响应验证是两件事。

## 初步参数与模型

每轴使用其正反两面均值，计算 `b=(mu_plus+mu_minus)/2`、`S=(mu_plus-mu_minus)/2`、`k=16384/S`。实验输出为 `round((raw-b)*k)`，保持16384计数/g；Y的b为负，因此Y实际相当于加约535计数后再乘比例。

| 轴 | 零偏b，计数 | 灵敏度S，计数/g | 比例k |
| --- | --- | --- | --- |
| X | +704.160256 | 16259.993590 | 1.007626474 |
| Y | -535.333333 | 16474.000000 | 0.994536846 |
| Z | +5288.416667 | 16664.250000 | 0.983182561 |

`bias_q16={46147847,-35083605,346581675}`，`gain_q16={66036,65178,64434}`。代码先将raw扩展为64位再乘65536，减去Q16零偏，乘Q16比例得到Q32；对称四舍五入，最终饱和到signed16。不存在对负整数直接右移或先在16位中减零偏的做法。

这一模型只修正三轴各自的偏置和比例，没有拟合交叉轴矩阵。原始CSV集合SHA256为 `dcbd9286b3d87c8eb1f10b19d063188e17efe6c178d1e0cc1dafb5468efaa493`，与参数头文件注释对应。

## 为何只是实验校准

| 姿态 | 本批数据校正后X/Y/Z均值，g | 横轴最大残差，g |
| --- | --- | --- |
| xp | +1.00000 / +0.06365 / +0.06562 | 0.06562 |
| xn | -1.00000 / +0.00506 / +0.07215 | 0.07215 |
| yp | -0.01606 / +1.00000 / -0.00241 | 0.01606 |
| yn | +0.01015 / -1.00000 / +0.02113 | 0.02113 |
| zp | -0.00951 / +0.01494 / +1.00000 | 0.01494 |
| zn | +0.13744 / -0.02226 / -1.00000 | 0.13744 |

表中是对拟合数据的回代，不是独立验收。主轴正负1g是两点计算的直接结果。xp/xn的Z原始均值均在6400附近，校正后仍有约0.07g，旧zn的X残差约0.137g。可能有摆放倾斜、偏置变化或交叉轴误差，现有记录无法区分，不通过强行旋转/扩大模型将其全部变成0。

全部记录太短、没有第二轮、没有跨重启/温度验证，新旧记录又跨阶段，所以仅支持实验初值。严格的量值校准仍按 `../docs/mpu6050_calibration.md` 补每面约20秒和独立第二轮。

## 实现文件与使用入口

| 文件 | 职责 |
| --- | --- |
| `host/calibrate_mpu6050.py` | 读取六份协议CSV、核查归档/字节/位/序号/时间，生成JSON、参数头文件与六份离线校正CSV |
| `stm32/app/accel_calibration.c/.h` | 64位定点校正、饱和位图及Keil可观察诊断 |
| `stm32/app/accel_calibration_params.h` | 当前实验系数与原始CSV集合指纹 |
| `stm32/app/acquisition.c` | 在宏启用时，对成功获取的真实传感器样本校正后再打包；固定源不校正 |
| `stm32/keil/vibration_calibration.uvprojx` | 独立SensorCalibratedTrial目标，APP_FIXED_SOURCE=0、APP_ACCEL_CALIBRATION=1 |
| `stm32/build_keil.ps1` | 保留原both行为，支持实验目标并生成AXF/HEX |
| `stm32/tests/test_calibration.c`、`check_calibration.py`、`test_calibration.ps1` | 全范围与应用集成、错误恢复、独立数值交叉核查 |

原 `vibration_monitor.uvprojx` 保持原两目标：`FixedSource`不变，`SensorSource`仍发送原始计数。新目标位于另一个工程 `stm32/keil/vibration_calibration.uvprojx`，不能在原工程下拉列表中找第三个目标。原始两目标未启用校准分支。

实验目标仍使用既有十字节布局、SEQ和XOR，但三轴字段含义为校准后的整数计数，包内没有校准模式标志；记录时必须写明固件目标。FPGA无需因本次STM32修改重建，raw回传仍应逐包匹配STM32输出，filtered/debug回传还要按原约定乘4恢复尺度。

Keil可观察 `g_accel_calibration.last_raw`、`last_corrected`、`samples`、`clipped_samples`、`last_clipped_axes`，以及原 `g_acquisition`。不要用停机调试时的周期证明采样时序正常。本次只编译和离线测试，没有连接DAP、烧录或新增采集。

实验构建命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File stm32/build_keil.ps1 -Target SensorCalibratedTrial
```

产物为 `build/stm32/SensorCalibratedTrial/vibration_monitor.axf`、`vibration_monitor.hex`。HEX共4808数据字节，记录校验和/单个EOF/Flash范围检查通过，地址范围0x08000000～0x080012C7。HEX SHA256为 `c897a1dc16b92755baf83764fd015590aba3d2950a1b0a86c843348e92ab25c4`。

AXF/HEX不是固化到芯片的证据。独立工程的实际下载器设置需按已有DAP方式确认，本次未替用户改写下载配置。

## 实际执行的检查与准确命令

在项目根目录执行，Python实际路径为 `C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`：

```powershell
python -X utf8 host/calibrate_mpu6050.py --output build/mpu6050_calibration_trial_20261031_v2
powershell -NoProfile -ExecutionPolicy Bypass -File stm32/test_portable.ps1 -Python 'C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File stm32/test_calibration.ps1 -Python 'C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File stm32/build_keil.ps1 -Target both
powershell -NoProfile -ExecutionPolicy Bypass -File stm32/build_keil.ps1 -Target SensorCalibratedTrial
```

第一条实际执行时使用上述完整Python路径；复跑时必须换新输出目录，脚本拒绝覆盖原分析。最终JSON为本报告同名 `.json`。软件检查结果：

- 原可移植C：65536个编码值及32个C/Python向量通过。
- 校准C：原位/非原位、空指针、诊断复位、传感器未就绪、I2C失败及重试恢复、发送失败与SEQ缺口、固定源绕过校正，实际通过。
- C/Python：三轴各65536输入，共196608轴值；实际C输出65536包均通过独立协议解码、精确有理数参考、单调性和饱和位图检查。与理想浮点校正相比，最终整数输出每轴最大差1计数。
- 全输入扫描中的饱和输入数为X952、Y355、Z4728；这是数值边界覆盖，不是实物采集中发生了这些次数的饱和。
- Keil：FixedSource、SensorSource、SensorCalibratedTrial均实际重建，0错误、0警告。
- 六个原归档CRC及原CSV/归档SHA256保持一致；脚本中文注释UTF-8 BOM核查通过。

本次未修改RTL，因此未重新执行ModelSim/XSim或Vivado；没有把C测试写成FPGA新增功能或实物精度通过。原v1.0-rc1及补交证据包未修改；本次为冻结后实验修正，尚未新冻结正式候选。

证据已归档到 `report/evidence/calibration_trial_20261031/`：六份逐样本校正CSV、最终分析JSON、参数头文件、原始与实验软件检查日志、Keil日志，以及65536包实际C输出的ZIP。ZIP CRC和内部二进制SHA256核查通过；`validation.json`记录12项源文件指纹、AXF/HEX指纹及软件/实物结果的区别。六份原始CSV和六份原始波形在分析后再次核对SHA256，均未改变。

## 下一步

可以用实验固件先查看大偏置是否显著改善，但不能据此判定正式校准完成。用于重新估计参数的长记录应切回原 `SensorSource`，因为实验固件的D0已经是校正值，不能再次当作原始数据做二次标定。

优先重新采齐同一次预热后的六面各20秒，补初始化回读证据；再重新摆放采第二轮，用第一轮固定参数验证第二轮。重点重做X正反面的垂直支撑和Z朝下的水平支撑，记录实际姿态。随后检查新的4ms周期分布、raw回传一致性、滤波尺度与窗口RMS；报警阈值仍是演示值，需在真实场景单独评估。
