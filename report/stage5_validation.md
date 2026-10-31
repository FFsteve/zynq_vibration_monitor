# 第五阶段实现验收记录

日期：2026-10-31。结论：**第五阶段软件验收通过；没有执行本阶段上板测试。**

用户已批准128样本窗口、三轴MS/整数RMS/绝对峰值、2000置位/1500解除及连续两窗确认，并授权四个新RTL、自检和自动ModelSim/XSim仿真。设计合同见 [设计说明](../docs/stage5_design.md)，复现见 [操作指南](../docs/stage5_test_guide.md)，机器可读结果和源码哈希见 [验收快照](stage5_validation.json)。

## 实现内容与用途

| 文件 | 职责 |
|---|---|
| `rtl/isqrt_u36.v` | 36位无符号逐二位开方，18拍输出整数根和精确余数，无浮点IP |
| `rtl/window_features.v` | 三轴128样本非重叠窗口，完整精度平方累加、均方、RMS、峰值、窗口ID和首末SEQ；丢样时取消窗口 |
| `rtl/threshold_alarm.v` | 每轴滞回和连续窗口确认，区分报警状态有效性与新窗口事件；质量失效不伪造正常解除 |
| `rtl/feature_monitor_core.v` | 连接既有UART/滤波与新计算支路，门控质量、对齐特征和更新后的报警 |
| `sim/tb/tb_isqrt_u36.v`、`tb_window_features.v`、`tb_threshold_alarm.v`、`tb_feature_monitor_core.v` | 四个模块各自自检，包含正常、错误及恢复 |
| `sim/tb/stage5_check.vh`、`stage5_negative_cases.v` | 统一完成/评分/看门狗及八项非法参数顶层 |
| `host/stage5_reference.py`、`stage5_vectors.py`、`check_stage5_captures.py` | 独立整数参考、确定性向量及实际RTL导出复核 |
| `sim/run_stage5.ps1`、`check_stage5_negative.ps1`及ModelSim/XSim脚本 | 双工具自动运行，检查当前结果文件，拒绝历史PASS |
| `scripts/check_stage5_synthesis.ps1/.tcl` | 隔离检查完整内部核心资源、布局布线及20ns内部时序 |
| `docs/stage5_design.md`、`stage5_test_plan.md`、`stage5_test_guide.md`、本记录及JSON | 接口/时序合同、验收标准、操作和实际证据；README/上下文/后续任务/AI日志同步 |

窗口默认512ms名义更新，三轴输入signed18，均方unsigned35、RMS与峰值unsigned18。默认能量累加43位；最负输入-131072的RMS和绝对峰值正确为131072，不回绕为负数。窗口只统计FIR历史完整的有效数据，前三轴滤波输出中的62个补零瞬态不计入。

新结果是内部接口。本次未改既有通信/滤波模块、板级top、STM32、XDC、Vivado本地工程或烧录设置，原始十字节回传继续使用原协议。没有加入PS/AXI/Linux或新结果包。

## 实际执行命令

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage5.ps1 -Simulator both
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage5.ps1 -Simulator both -Test window_features
& 'C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 host/check_stage5_captures.py --simulator modelsim
& 'C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 host/check_stage5_captures.py --simulator xsim
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_stage5_synthesis.ps1
```

先完成整套双工具检查，再补齐窗口全部在途阶段复位用例、对该模块进行双工具针对性回归，最后重新核对两套实际导出。完整日志为 `build/stage5_full_run.log`，窗口最终日志为 `build/stage5_window_final.log`，OOC日志为 `build/stage5_synthesis_run.log`。仿真使用ModelSim SE64 2020.4、XSim/Vivado 2020.2；Python运行时NumPy为2.3.5，开方/统计参考使用Python无界整数和math.isqrt。

仿真器在已获授权的正常进程环境运行，以避开此前受限执行环境的ModelSim DLL/XSim子编译问题；没有更改Windows安全配置、工具安装或许可。PowerShell脚本含中文注释，均为UTF-8 BOM。

## 双工具最终自检结果

| 自检顶层 | ModelSim检查数 | XSim检查数 | 错误数 |
|---|---:|---:|---:|
| `tb_isqrt_u36` | 231556 | 231556 | 0 |
| `tb_window_features` | 131447 | 131447 | 0 |
| `tb_threshold_alarm` | 10365 | 10365 | 0 |
| `tb_feature_monitor_core` | 94715 | 94715 | 0 |

每项均检查实际仿真完成、错误计数、工具退出状态和新写入结果。脚本开始时将结果标为NOT_RUN；没有把预期或数值模型冒充RTL通过。

### 算术、时序和恢复覆盖

- 开方：10033个36位输入，与独立math.isqrt、根不等式及精确余数全一致；检查18拍输出、19拍最早接纳、忙时脉冲、保持请求，以及每个迭代位置复位取消/恢复。
- 窗口：109个默认窗口，共13952组三轴输入，包含零、异号常量、正负满量程、交替极值、首末冲激、整周期正弦、101个固定种子随机窗口。逐窗MS/RMS/峰值/SEQ/ID全部精确相等。首末冲激相同，最后一项未遗漏。
- 参数边界：窗长1、2、4、128、1024；确认数1、2、255；最大阈值131072及其平方2³⁴，均通过。
- 取消与恢复：窗口末样本接纳后22个在途位置分别注入clear、rst和忙时事件，覆盖乘法、累加、开方开始/运行/提交边界；计数、长期clear、无旧结果、SEQ回绕/跳号/重复和完整恢复窗口均通过。
- 报警：5008拍定向/随机输入，覆盖ON/OFF平方前后及相等、死区打断连续确认、三轴独立、空闲保持、clear优先及不伪造解除。实际RTL逐拍导出与Python一致。

### 真实UART位流集成

主通道从实际TB UART位流进入原解析/滤波链路，输入1600个合成低/高/低振动包；不是把内部filtered_valid伪造为UART结果。12个完整窗口的全部特征及报警与Python精确一致，报警位序列为：

```text
0 0 5 5 5 5 5 5 5 0 0 0
```

这里5表示X/Z报警、Y不报警。变化发生在连续两个满足门槛的窗口之后，恢复低振动后按两窗规则解除。每个新窗口均与更新后的报警同拍；实际延迟从解析器raw_valid脉冲到对齐结果为218拍。

继续覆盖九处截断、坏校验、错误包头、停止位错误、断流、主动SEQ跳变及全局复位；其后600个恢复包形成三个完整恢复窗口。全部2200个合法包的十字节原始回传均由独立按位解码逐字节核对一致，坏帧未产生统计样本。首次缺包/断流后重新预热并凑满窗口，ID仅在全局复位后归零。

主通道时间压缩50倍（每位10拍、包间约4000拍），不声称测得实际250Hz稳定性。另有真实默认50MHz/115200、434拍/位的三包冒烟通道，检查完整原始回传和滤波序号回绕。

单独辅助通道定向注入历史不足、饱和、滤波过载、重启、窗口过载、不连续及适配层发布边界故障，检查无效状态、取消与恢复。该通道明确只验证质量门控，不替代UART和滤波算术证据。

### 实际导出与非法参数

两工具各导出109个窗口、12个UART集成窗口及5008拍报警状态，Python逐项相等；另检查每个RMS的整数根不等式和峰值界限。

八项非法RTL配置（窗长对数-1/11、阈值相等、ON越界、ON为0、OFF为负、确认数0/256）在ModelSim/XSim均主动拒绝，拒绝标记正确，未到达正常运行哨兵。设计参考中的额外数值越界检查只算Python证据，不计成RTL测试。

## 隔离布局布线结果

OOC顶层为完整 `feature_monitor_core`，包含通信、第四阶段滤波和第五阶段，不是只综合新增窗口。器件 `xc7z010clg400-1`，时钟20ns；实际完成综合、优化、布局和布线。

| 项目 | 实际结果 |
|---|---:|
| LUT | 3205，18.21% |
| 触发器 | 5894，16.74% |
| DSP48E1 | 6，7.50% |
| BRAM / 锁存器 | 0 / 0 |
| 内部建立裕量 | 9.063ns |
| 内部保持裕量 | 0.088ns |
| 无时钟寄存器 / 未约束内部端点 | 0 / 0 |

内部时序通过，无DRC Error/Critical Warning。**并非零警告，也不是板级时序签核：**

- DRC有3条DPOP-1（FIR的DSP输出寄存建议）、3条DPOP-2（平方乘法器流水建议）、1条RTSTAT-10（OOC输出有269条网络尚无可布线路由负载）、1条ZPS7-1。没有屏蔽这些提示或引入PS。
- OOC未设置父级 `HD.CLK_SRC`，时钟延迟/偏斜仍依赖最终集成；输入rst/pl_rx没有父级分区位置，2个输入和846个输出未设置接口延迟。没有虚构0ns接口预算，也没有添加false_path隐藏内部问题。
- 输出的真实消费路径、板级时钟、复位、异步UART约束和最终完整时序留待整体集成。资源/内部路径通过不能推广为新功能上板成功。

## 本次纠错

1. 设计初稿把解析器raw_valid到对齐特征记为217拍；实际218拍，多出的是进入第四阶段滤波器的一拍。已修正文档/TB为4.36us，不修改正确流水或放宽时钟。
2. 集成复位测试开始时立刻发UART，首包被既有WAIT_HIGH策略丢弃。激励改为复位后保留20拍高电平（压缩通道位宽10拍），重新测试全部合法包一致；没有改动既有UART RTL。
3. 标注未用输出的辅助编辑规则一度跨模块声明添加错误端口，导致编译失败。修正规则、明确空连接后，完整双工具重跑通过；首次失败日志不算通过证据。

## 剩余风险和下一步

2000/1500为未校准的演示计数阈值，不是实际故障标准。名义512ms窗口及频率结论依赖均匀250Hz；MPU6050配置回读、零偏/比例校准、长记录和真实采样稳定性仍未完成。质量失效时必须读alarm_valid，不能将alarm=0解读为正常。

本阶段软件完成，用户可继续后续阶段具体设计；结果传输方案若涉及协议变更，须先获批准。最终阶段统一接入板级top、完整时序检查和上板验证，届时才评估实物振动、RMS变化及报警表现。
