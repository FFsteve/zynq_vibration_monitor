---
name: fir-validation
description: 验证本项目的去直流、定点FIR和UART集成，执行Python参考与ModelSim/XSim自检并收集Vivado资源时序证据。用于滤波参数修改、回归或竞赛取证；不授权接线、下载或硬件操作。
---

# FIR定点验证

## 适用范围

用于本仓库的Verilog三轴去直流、63抽头串行FIR、窗口特征和UART集成修改。先确认根目录含AGENTS.md、rtl/和host/stage4_reference.py，再按当前协议及用户已批准的设计工作。技能本身不批准改变协议、添加PS或操作硬件。

项目根目录为本文件目录的上两级。本技能是可移交项目成果，没有自动安装到全局技能目录。

## 数值合同与入口

先查阅[滤波合同](../../docs/stage4_design.md)及受影响阶段设计。基线Q16更新1/32；系数signed18/Q16，乘积35位、累加41位、内部输出signed18。负数按最接近且半单位远离零舍入，不能静默改成右移截断。ROM有效地址仅0～62；重启、SEQ缺口、断流和过载不能泄漏旧历史。

从项目根目录用带NumPy的Python运行host/stage4_reference.py，再执行sim/run_stage4.ps1 -Simulator both；脚本支持-PythonExe、-ModelSimBin、-VivadoBin，不依赖固定PATH。操作和准确PowerShell命令见[第四阶段指南](../../docs/stage4_test_guide.md)。

数值参考不是RTL证据：使用无界整数点积、独立卷积和浮点基线交叉检查，覆盖最负值、半单位、窄输出饱和、脉冲、阶跃、随机及频率点；RTL仍要真正执行ModelSim和XSim，逐样本比较独立期望并覆盖正常、错误、恢复。

默认系数SHA256为b9b74fb39759cf352d2b388ea15650b0a1522d1f15dd6f4861f622d7b580fc35。改系数须同步参考、合同和脚本中的哈希，不得跳过校验。系数按LF字节写入，Windows文本换行曾导致真实磁盘哈希不一致。

## 集成与资源取证

窗口/报警改动运行第五阶段；完整回传改动运行第六阶段；最终全回归和冻结见[交付入口](../../docs/stage7_delivery.md)。滤波回传已批准右移2位，PC乘4还原仍有0～3计数量化，内部RMS使用完整18位，不覆盖原始字段。

OOC只证明内部路径，不等于板级签核。最终从源码重建system_top，检查50MHz时序、同步链、资源、DRC和未约束内部端点。原始模式未使用的计算支路曾被优化掉，仅网络MARK_DEBUG/KEEP不足：检查真实网表保留三轴FIR、三个开方器、报警及唯一外部UART发送器，包含调试保留的实际开销。

## 失败与证据

脚本先标记NOT_RUN；只有本次进程退出、TB完成、errors=0和新结果文件都满足才通过。负向测试必须明确拒绝且未到达正常运行哨兵，不能把任意退出当作通过。

ModelSim受限进程曾出现DLL重定位错误，XSim子编译也曾失败。记录实际启动问题，按已有授权选择正常执行环境，不改变系统安全设置、不把未运行写成通过。xvlog包含目录用-i，vlog用+incdir+。

保存准确命令、源码/系数哈希、当前日志、实际数据、失败修正和未验证项；报告放report/，重要纠错记report/ai_devlog.md。参考[第四阶段](../../report/stage4_validation.md)、[第六阶段](../../report/stage6_validation.md)和[最终回归](../../report/stage7_validation.md)，不以历史结果代替新版本执行。传感器校准、真实采样、接线和上板仍须独立验证。
