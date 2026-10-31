# 最终上板测试方案

日期：2026-10-31。本文是可执行的测试方案和判定标准，**不是本轮已执行的板测报告**。历史第三阶段基本通信证据仍有效；新版完整链路、滤波、窗口和报警的实物结果需按本方案记录。

## 1. 从哪里开始

先阅读 [交付入口](stage7_delivery.md) 和 [需求核对](../report/requirements_audit.md)。按下面顺序测试，不跳过固定数据通信就直接判断传感器或滤波好坏。

| 顺序 | 测试 | 需要什么 | 通过时看到什么 |
|---|---|---|---|
| B01 | 断电接线与供电复核 | 万用表、原理图 | 信号方向、电压、共地和跳帽符合图纸 |
| B02 | 下载原始版与FixedSource | JTAG、DAP、DL16 | D0/D1十字节逐字节相同，约4ms一包 |
| B03 | FixedSource滤波版 | 滤波或debug比特流 | D0仍为固定值，D1三轴为0，SEQ/XOR正确 |
| B04 | SensorSource初始化 | MPU6050、四路DL16 | 身份和关键寄存器回读正确，六字节与D0相同 |
| B05 | SensorSource原始回传 | 原始版 | 同次D0/D1完整包一一对应，不改变原始数值 |
| B06 | 较长记录和采样周期 | DL16 Stream或USB-TTL | 报告实际包数、周期分布、缺口和错误，不靠截图猜长期稳定性 |
| B07 | SensorSource滤波 | 滤波版 | D1解码后乘4，与输入事件序列对应的定点参考一致 |
| B08 | 内部窗口与报警 | debug.bit及同版system.ltx | ILA看到有效窗口、MS/RMS/峰值、ID和报警状态 |
| B09 | 受控数字频率与报警 | 另加3.3V USB-TTL | 已知数字激励回包精确匹配参考，三轴/门槛行为可复现 |
| B10 | 中断、重启及冷启动 | 按键/供电操作、完整记录 | 失效与重新预热正确，重配后无旧窗口和旧报警 |
| B11 | 传感器 量值与校准 | 六面静止、重复记录 | 查明偏差与实际配置，另立校准结果，不以去直流代替 |
| B12 | 最终演示归档 | 全部成果及哈希 | 从冷启动按相同步骤重复，证据和版本可对应 |

现有JTAG、DAP、DL16足够进行B02～B08的主要观察。**精确数字频响和自动逐包参考比对的B09需要额外USB-TTL发送通道**；没有该设备或受控机械激励时，把严格实物频响标为待验证，不能用手摇频率替代标准源。输出拥塞已在自检中覆盖，板级暂停固定0，不要求现场短接信号制造拥塞。

## 2. 程序和下载文件

交付包位于 `build/release/v1.0-rc1/`：

| 文件 | 用途 |
|---|---|
| `fpga/raw/system.bit` | 原始十字节回传，RETURN_FILTERED=0 |
| `fpga/filtered/system.bit` | 滤波十字节回传，RETURN_FILTERED=1，三轴解码后乘4 |
| `fpga/debug/system.bit`与`system.ltx` | 滤波回传加ILA内部观察，必须使用同一版配对文件 |
| `stm32/FixedSource/vibration_monitor.axf/.hex` | 常量1、-1、-32768，约4ms一包 |
| `stm32/SensorSource/vibration_monitor.axf/.hex` | I2C2轮询MPU6050并发送原始数据 |
| `board_vectors/` | 离线生成的受控数字激励和准确期望 |
| `release_manifest.json` | 源码、下载文件与证据SHA256 |

程序输入和输出仍使用115200、8数据位、无校验、1停止位、低位先发。滤波包**没有模式标志**，测试记录中必须写raw或filtered；debug版也是filtered尺度。包内没有RMS/报警字段，这些量通过ILA观察。

原本地Vivado工程仍以旧top为入口；本轮最终成果由 `system_top` 独立构建。测试使用上述新文件，不直接重下旧工程。FPGA JTAG配置掉电后不保留，本方案每次冷启动重新配置PL；本轮没有制作QSPI/SD启动镜像，也不要求学习PS。STM32程序写入内部Flash后可掉电保存，启动设置保持此前已经验证的配置，不更改BOOT或下载器选项。

## 3. 断电接线和供电

下表经本轮重新读取实际图纸复核，仍须根据实物1脚标记辨认。K14/M15/U18是芯片封装号，杜邦线实际接排针，不接BGA焊球。

| 信号 | 从哪里 | 接到哪里 |
|---|---|---|
| STM32发送 | PA9，扩展板通讯接口3的J9/J10.3，或J31.5 | FPGA底板J3.1/UART2_RX，对应K14 |
| 共地 | STM32 GND，例如通讯接口3的.5 | FPGA底板J3.37或.39 |
| FPGA回传探测 | FPGA底板J3.2/UART2_TX，对应M15 | DL16 D1；需要COM采集时再接USB-TTL RXD |
| MPU6050供电 | STM32扩展板通讯接口2 J3/J4.6，VCC4 | 模块3V3，先确认VCC4为3.3V |
| MPU6050地 | 同接口.5 | 模块GND |
| I2C时钟 | 同接口.3/PB10 | 模块SCL |
| I2C数据 | 同接口.4/PB11 | 模块SDA |

MPU6050的INT当前不接，AD0使用模块已有下拉。STM32扩展板J32的2—3接通选择VCC4=3.3V，1—2为5V；不能凭跳帽朝向判断。先测量再断电接模块。两块板上的同名J3不是同一连接器。

FPGA底板P1中UART2与COM2/RS232/RS485的连接需隔离，尤其不能让SP3232接收输出和PA9共同驱动K14。DB9的RS232不能直接接GPIO。不要把PA9接FPGA TX，也不接PA10形成无用回路；外置串口只做接收时TXD悬空，VCC不接板卡。

两板使用各自符合说明的电源，不互接3.3V/5V。FPGA下载器不能作为整板正常电源；DAP是否给STM32供电取决于实物接法，必须实际确认。DL16仅并接输入与地，PWM0/PWM1关闭且不接现有信号。

本方案不新增复位/LED端口。旧呼吸灯例子的N16/J16不在本程序端口内，板载LED不能作为本项目功能验收依据。时钟由板载PL振荡器提供，不从STM32另接时钟。

## 4. 电脑与设备的连线

必须连接：FPGA JTAG下载器USB、STM32 DAP USB/SWD、DL16 USB及其输入探头。另确认两板正常供电。

需要PC COM口收包时，另加3.3V USB-TTL，RXD接FPGA J3.2、GND共地，再接USB到电脑。领航者板载USB串口不是当前UART2/K14/M15的等价入口，不仅凭插了板载USB就等待回包。

STM32板载USB桥默认观察PA9原始发送，可以作为D0观察通道；不要把它和FPGA回包混淆，也不要在未隔离PA9时把M15再接同一个桥RXD。原 [接线指南](wiring_guide.md) 有路径说明。

## 5. 手动下载顺序

1. 保存当前接线/跳帽照片，完成B01后上电。暂时按住STM32复位，或先不要让采集程序运行。
2. Vivado打开Hardware Manager，连接实际JTAG目标，在Zynq链中选择PL的xc7z010器件，使用本次需要的system.bit。**本轮脚本没有代为连接或下载，下面操作由操作者执行。**
3. 初次选raw版。Program Device成功后，确认下载的文件路径与release_manifest哈希相符。
4. Keil打开 `stm32/keil/vibration_monitor.uvprojx`，选择FixedSource，使用原已验证的DAP设置下载并运行。也可以用交付HEX通过原有烧录工具写Flash，不另改地址或启动配置。
5. 先设置DL16并开始立即采集，再释放STM32复位。FPGA先配置、STM32后发送，便于完整捕获首包和初始化。
6. 更换FPGA模式时停止记录，重新配置对应bit，再开始新的记录。每份记录注明模式；严格参考测试每个激励都先重配FPGA，不能沿用上一次基线/窗口ID。

使用debug版时，在Program Device同时选择debug目录的system.bit和system.ltx。不要给普通filtered比特流加载debug的ltx。若ILA未发现，先核对配对文件、目标、JTAG频率和50MHz时钟，不自行加入PS或改芯片电压；JTAG可先使用6MHz或更低的可用设置。

## 6. DL16设置

| 通道 | 接点 | 解码 |
|---|---|---|
| D0 | FPGA J3.1，观察STM32发送线 | UART |
| D1 | FPGA J3.2，观察FPGA回传线 | 另一个UART |
| D2 | STM32通讯接口2 PB10/SCL | I2C SCL |
| D3 | STM32通讯接口2 PB11/SDA | I2C SDA |
| G | 已共地的板卡地 | 地 |

短通信记录先用Buffer、20MS/s、1.6V门限，4路，100ms。启动及窗口测试用**立即采集、至少2秒实际记录长度**，在采集中尽早复位STM32。四路20MS/s、2秒裸采样为160Mbit，低于DL16的1Gbit硬件缓存；仍要核对软件实际深度，不能保留截图中的4MS/ch却认为已记录2秒。

较长记录建议Stream，选择软件支持的2～5MS/s、60秒；2MS/s下UART约17个采样点/位，适合协议检查，不用于高速毛刺验收。若无该档位，按可用采样率与电脑内存调整并记录。DL16没有Roll模式；循环是重复采集，不等于连续无缝长记录。

两个UART都设115200、8、none、1、lsb-first、hex、非反相。每个解码器将TX选择对应被观察通道、RX留空，这只是解码角色，不会驱动线路。采样点50%；包长可设10，包内无结束分隔符，不把某个数据字节当包尾。

I2C选择D2为SCL、D3为SDA，十六进制。以7位地址0x68解释；若界面显示原始八位地址，写D0/读D1也正确。正常读事务最后一个字节由主机NACK结束，不将该NACK判为器件异常。

DL16手册与实际ATK-Logic版本可能菜单措辞不同，以功能和真实记录区间为准；完整既有操作见 [分析仪指南](logic_analyzer_guide.md)。

## 7. B02/B03：固定数据先验收

下载FixedSource、FPGA raw版，捕获至少100个完整包。应为：

```text
A5 5A SEQ 00 01 FF FF 80 00 CHK
CHK = SEQ XOR 81
```

三轴分别为1、-1、-32768。SEQ应按模256递增，D0和D1同SEQ整包一致。标称位时间8.68us、字节86.8us、十字节868us、包起点4ms。任意高/低平台可能包含多个同值数据位，不直接用其倒数判断波特率。

随后只更换为filtered或debug版并重启FixedSource。此时每次都输入同一常量，基线第一样本建立，因此**从第一个滤波结果起三轴均为0**，包为：

```text
A5 5A SEQ 00 00 00 00 00 00 CHK
CHK = SEQ
```

D0仍发送原始常量；D1是0不等于STM32停止发送。内部FIR历史到第63个样本才完整，窗口第一项索引62，首个128样本窗口末项索引189，约首样本后756ms再加数字延迟。此后名义每512ms一个窗口，RMS/峰值为0、alarm_valid=1且alarm_axes=0。

判定失败时先查模式、接线、供电、下载版本和UART参数，再查数据算法。回包与输入可在输入最后停止位结束前有轻微重叠，因为RX在停止位中心确认成功；延迟比较以同一包的明确边沿或内部raw_valid为基准。

## 8. B04/B05/B11：SensorSource配置、通信与量值

更换Keil SensorSource并重配FPGA raw版。立即采集至少2秒，在窗口内复位STM32。当前程序约有两段100ms初始化等待，身份或配置失败时约一秒后重试，不要求上电即有均匀数据。

核对I2C：WHO_AM_I寄存器0x75应读到0x68；复位后写入并回读以下配置：

| 寄存器 | 预期值 |
|---|---|
| 0x6B | 0x01 |
| 0x1A | 0x02 |
| 0x19 | 0x03 |
| 0x1C | 0x00 |
| 0x38 | 0x01 |

正常采样轮询0x3A，DATA_RDY置位后从0x3B连续读6字节。按高字节在前还原signed16，必须与同组D0的XYZ一致，再与D1同SEQ核对。Keil可观察 `g_acquisition.online/who_am_i/sensor_errors/tx_errors/late_samples`；暂停CPU观察会扰动时序，不用断点停机期间的记录证明采样稳定性。

此前正反静止的Z值支持较大偏置，但初始化实测和完整校准仍待补。先保存六面各至少10秒静止原始记录，重复一轮，记录姿态、均值、标准差、温度/时间条件；通过实际配置回读后才能使用相应LSB/g换算。不要直接把约5288计数写成已标定补偿，也不要因滤波静止输出接近0就判定MPU6050量值已正常。

通信通过与量值通过分开填写。若需要写入补偿或改传感器配置，形成后续版本，重新做受影响测试，不能修改冻结包后继续引用原哈希。

## 9. B06/B07：长记录与滤波对照

至少做一份60秒记录。对完整包统计总数、SEQ回绕、重复、缺口、XOR/停止位错误、实际包周期均值/最小/最大及异常段；保存原始atkdl和UART/I2C CSV。250包/s为名义目标，报告实际周期分布。操作系统接收分块时间不是线缆采样时间，超过一整圈SEQ的间断也不能唯一推出丢包数。

只凭首尾截断不判整个链路坏，先划定完整记录区间；也不能丢掉中间错误后宣称零丢包。UART带宽余量不是采样稳定性的证明。

可用独立USB-TTL只接收FPGA输出，保存原始二进制：

```powershell
python -X utf8 host/capture.py --port COM7 --seconds 60 --output build/board_runs/sensor_raw_01
python -X utf8 host/check_stage6_captures.py --input-bin build/board_runs/sensor_filtered_01/capture.bin --source-mode filtered --output build/board_runs/sensor_filtered_scaled_01
```

COM7为示例，改成设备管理器中的实际端口；输出目录必须是新的。第二条命令要求此前确实采集并保存了sensor_filtered_01，不能拿raw记录假装filtered。

滤波测试同时捕获D0/D1，按同SEQ配对。D1 signed16解码后乘4，不能直接与D0原始计数比振幅。若记录没有包含滤波首次基线建立，则无法精确重建初始状态；应从FPGA重配和STM32启动前开始记录，或明确仅做稳定段近似比较。中断/SEQ重启后的前62个输出为预热，特征另需完整128样本窗口。

物理频响要有已知频率/振幅的机械激励和参考测量；普通手动晃动只用于趋势演示，不把它记录成精确5～30Hz或60Hz验收。

## 10. B08：ILA观察内部窗口和报警

加载debug版配对bit/ltx，Hardware Manager应出现stage7_ila。完整探针对应 `fpga/debug/probe_map.tsv`：probe0=feature_valid、probe1=quality_valid、probe2=alarm_valid、probe3=alarm_axes、probe4=window_id，之后是首末SEQ、三轴MS/RMS/峰值和诊断。

MS、RMS、峰值设置**无符号十进制**；它们不能按signed18解释最负输入的绝对值131072。alarm_axes bit0/1/2分别为X/Y/Z，阈值是原始计数2000置位、1500解除，默认连续两窗。

初次用FixedSource，触发条件设feature_valid=1，采集后查看对应窗口的全部字段。1024点、50MHz的普通连续采样只覆盖20.48us，足以看到一次窗口提交及前后保持值，**不能把它当成连续512ms的振动波形**。本调试快照额外延迟一拍，所有字段一同延迟，不改变功能链路。

要观察置位，触发alarm_axes非0且alarm_valid=1；要观察正常解除，设alarm_axes=0且alarm_valid=1，并先确认此前已报警。quality/alarm_valid变0属于数据失效，不是正常振动解除。采集条件功能已启用，可选择只保存feature_valid=1的样本，但1024个窗口约524秒，不应误以为很快采满；新手先使用普通触发抓单次快照。

测试报警时不能只用静止固定源；用B09的alarm_cycle受控数字激励，或用已确认幅值足够的物理振动，结合对应窗口CSV判定。不要为了让灯亮而临时改变阈值；当前没有报警LED输出。

## 11. B09：受控数字激励，绕过传感器

这条路径只验收FPGA数字链路、滤波和报警，不证明STM32/MPU6050工作。需要一个双向3.3V USB-TTL，发送线和接收线都可用。

1. 断电，**断开STM32 PA9→FPGA RX**，保留公共地；P1相关收发器仍隔离。
2. USB-TTL TXD→FPGA J3.1/K14，RXD→J3.2/M15，GND共地，VCC不接。不能让USB-TTL TXD与PA9并联输出。
3. 用DL16并接D0/D1，先配置FPGA raw版，确认USB串口115200、8N1，无RTS/DTR连线。
4. 每个fixture都重新配置FPGA，确保基线、窗口ID和报警从初态开始，再执行回放。

```powershell
python -X utf8 host/board_test.py generate --output build/board_vectors
python -X utf8 host/board_test.py replay --fixture build/board_vectors/fixed --source-mode raw --port COM7 --output build/board_runs/fixed_raw_01
```

第一步只生成离线数据，不接触硬件。第二步是**实际发送命令**，仅在完成上述隔离接线、确认端口和模式后由操作者运行。对filtered/debug模式把source-mode改为filtered，并选择相符bit。已有输出目录会在打开任何串口前拒绝覆盖。

可用激励：fixed、tone_5hz/10hz/20hz/30hz/50hz/60hz/80hz/100hz、alarm_cycle。各频率为X轴幅值9000计数的2500样本，另两轴0；alarm_cycle先低、再高、最后低，1600样本。每个目录含输入、预期raw/filtered二进制、expected_features.csv及身份/哈希。

工具将收到的完整线缆字节与精确参考比较，成功标记PASS_DIGITAL_CONTENT；用debug版时再将ILA窗口ID/MS/RMS/峰值/报警与同fixture的expected_features.csv核对。所有在途采样都由UART事件推进，正常下不应丢包；短写失败立即停止，不集中补发赶时间。

PC调度和USB缓冲不保证实际250Hz。即使字节完全匹配，也须用DL16核对线上周期；若间断超过12ms，FPGA会重建历史，参考不应再匹配，应记录失败、检查调度后重做。工具不会自动把数字内容通过写成物理时序或传感器标定通过。

## 12. B10：中断、复位和冷启动

不建议带电拔插单根信号制造毛刺。可保持接线，按住STM32复位或停止PC回放，观察超过12ms无有效包后quality/alarm_valid失效；重新发送后重新建立历史，前62项不用于窗口，完整128项后才发布新窗。

STM32重启通常SEQ重新从0开始；SEQ重复/跳号要重建，但首包恰好与旧期望一致时未必触发SEQ错误，因此同时记录实际间断。短停顿未达到断流阈值且SEQ连续时不要求错误重启。

FPGA全局复位通过**重新配置相应比特流**完成，不能直接按N16按键就认为清了内部状态。重配会终止当前串口字节，捕获边界可能有截断；新一轮从干净启动后，队列/诊断/window_id归零、基线和FIR重新建立。不要将重配时的半包当作稳态协议错误。

至少重复3轮：关电→确认接线→FPGA上电并重配→开始采集→启动STM32/fixture→观察首个完整窗口。分别记录启动时间、首包SEQ、首个有效窗口与最终状态。FPGA掉电不保留JTAG比特流，STM32 Flash仍保留程序；这两者不能混淆。

## 13. 记录、判定与故障定位

每个测试目录保存：测试编号、日期/操作者、连接照片、bit/ltx/HEX哈希、模式、采样参数、原始atkdl/bin、解码CSV、日志、预期、实际、通过/失败/未验证及原因。使用 [板测记录表](../report/final_board_record.md)，不能只保留截图。

| 现象 | 优先检查 |
|---|---|
| D0没有波形 | STM32供电/运行目标、DAP是否仅调试供电、SensorSource初始化、PA9探点 |
| D0正确、D1无波形 | FPGA是否配置了本版system_top、供电/时钟、共地、RX接线与P1隔离 |
| 乱码或停止位错误 | 波特率/反相/通道、逻辑电平、地线、实际位宽、是否只在截断边界 |
| filtered振幅缩小约4倍 | 先确认是否忘了乘4，不直接改FIR系数 |
| ILA未出现 | bit/ltx配对、是否下载debug版、PL时钟、JTAG目标/速率 |
| RMS/峰值像负数 | ILA显示类型应为无符号 |
| 窗口长时间不完成 | 实际断流/SEQ跳变、历史预热、是否每次都在重启，而非先改窗口长度 |
| 静止原始Z偏大 | 回读配置、六面静止/校准，通信一致不代表量值正常 |

首次失败先归档证据，不修改冻结版后继续引用旧哈希。修复后建立新版本并重跑受影响测试。B01～B12逐项完成之前，只能说软件/构建已验收，不能说整个实物项目完全通过。

## 14. 资料依据

FPGA路径见 `docs/hardware/zynq_core_2v5.pdf` 第3/7/10/12页、`zynq_baseboard_v3_9.pdf` 第1/5页；MPU6050引脚和单位见模块原理图第1页、模块手册第5/7页。STM32扩展板原理图物理第3/4页、核心板原理图第4/5/6页的原文件路径见 [板级核查](stm32_board_review.md)。DL16依据用户提供的 `F:/说明书/ATK-Logic_CN.pdf` 物理第5/6及19～30/34页，本轮重新读取并核对页面图像。

ILA插入与探针文件流程参考[AMD UG908调试核非工程模式流程](https://docs.amd.com/r/2025.2-%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87/ug908-vivado-programming-debugging/%E5%9C%A8%E9%9D%9E%E5%B7%A5%E7%A8%8B%E6%A8%A1%E5%BC%8F%E4%B8%8B%E6%89%A7%E8%A1%8C%E8%B0%83%E8%AF%95%E6%A0%B8%E6%8F%92%E5%85%A5?contentId=08FNQXdzP4xOVcp01~xW3A)；具体参数已由本机Vivado2020.2实际生成和实现验收，不以新版网页示例代替本机结果。
