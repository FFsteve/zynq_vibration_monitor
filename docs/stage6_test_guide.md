# 第六阶段操作与复现指南

## 当前入口

原计划第六阶段是系统联调与量化，第七阶段是全部回归、修复和交付，见 [分期计划](stage_plan.md)。本阶段新增 `system_top`，原 `top` 和原Vivado工程仍作为此前通信入口；不能在旧工程直接下载旧顶层后预期看到新增滤波回传。

软件仿真、实际量化与板级实现结果见 [验收记录](../report/stage6_validation.md)。实物项独立列在 [板测记录](../report/stage6_board_record.md)，未执行前不写通过。

## 自动仿真

在仓库根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage6.ps1 -Simulator both
```

脚本先生成独立参考，核对第四阶段系数，再运行三个新模块自检、原队列和解析器针对性回归、实际RTL导出对照及两个非法模式测试。输出位于 `build/modelsim_stage6/` 和 `build/xsim_stage6/`。结果文件预先置为NOT_RUN，必须本次完成、errors=0且进程正常退出才通过。

单独运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage6.ps1 -Simulator modelsim -Test system_monitor_core
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage6.ps1 -Simulator xsim -Test system_top
```

其他测试名称为 `return_source_select`、`return_controller`、`packet_parser`。只有默认all会在各模块后自动执行整批导出和负向检查。

默认工具目录为 `D:\modelsim\win64`、`D:\Xilinx\Vivado\2020.2\bin`；可传 `-ModelSimBin`、`-VivadoBin`、`-PythonExe`。Python参考/量化需要NumPy。ExecutionPolicy Bypass仅用于本次子进程，不修改系统策略。

主系统通道使用每位10拍、每样本4608拍的压缩参数，严格对应名义250包/s；不是实物长时间采样。默认参数顶层另测50MHz/115200、434拍位宽、200000拍包周期和三种回传配置。

## 查看波形和实际数据

ModelSim每个测试目录保留 `vsim.wlf`，XSim保留 `stage6_<模块>.wdb`，分别用ModelSim打开波形或Vivado的 `File -> Simulation Waveform -> Open` 打开。

系统测试同时实例化raw_case和filtered_case。观察 `rx/tx/pause`、`raw_valid/filtered_valid/fv`、`full/quality/av`、`axes/wid` 与真实输出队列的 `accepted/dropped/completed/queued`。

`pause`只在内部自检使用，板级固定0。高电平期间正在发送的字节完整完成，后续握手等待；默认队列最多在途1包加等待4包。暂停期间滤波和窗口继续运算，队列满只丢新包，撤暂停后按顺序发送。

各系统测试目录保存原始及滤波两套 `wire_*.bin`、`internal_*.txt`、`features_*.txt`、`latency_*.txt`。它们来自实际RTL，不是Python回填的“仿真结果”。重新分析：

```powershell
python -X utf8 host/check_stage6_captures.py --simulator modelsim
python -X utf8 host/check_stage6_captures.py --simulator xsim
```

量化使用主合成序列索引1000～3999，长度3000、剔除预热，拟合10/30/60Hz三轴幅值。完整18位内部结果和线缆还原值分别报告，不能把缩放量化后的结果当作18位无损传输。

## 两种模式的独立板级实现

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_stage6_implementation.ps1
```

脚本分别以 `RETURN_FILTERED=0/1` 构建 `system_top`，结果位于 `build/stage6_implementation/raw/`、`filtered/`。复用已核对的三端口约束，读取新层次专用CDC约束，保存资源/时序/DRC/CDC/IO、分支保留检查和 `routed_system.dcp`。

检查全部计算支路在原始模式也保留，旧的未连接发送支路应被移除；三个RMS开方器、三轴FIR、窗口和报警必须存在。427位 `MARK_DEBUG/DONT_TOUCH` 内部快照寄存器为计算支路提供保留负载；不会自动插入ILA，也不能仅凭标记就在PC上看到RMS/报警。

本脚本不打开原本地工程、不生成比特流、不连接Hardware Manager、不烧录。最终阶段在冻结源码和确认剩余DRC事项后安排下载；不能把本阶段实现报告写成已运行在板上。

## 回传模式与实物记录换算

用户已批准以综合参数选择模式：

- `RETURN_FILTERED=0`：原始十字节回传，三轴保持原始signed16计数。
- `RETURN_FILTERED=1`：滤波结果算术右移2位回传，signed16解码后乘4恢复计数尺度；与原18位结果相差0～3计数。
- `ACK_ONLY=1`：兼容06应答，用于通信诊断，不用于滤波量化。

包内没有模式标志；保存下载版本、模式、系数哈希和记录元数据，禁止自动猜模式。第五阶段窗口和报警仍使用完整18位数据，当前十字节包没有承载RMS或报警字段。

实测时沿用 [接线指南](wiring_guide.md) 和 [DL16操作方案](logic_analyzer_guide.md)。已存在的 `host/capture.py` 可保存独立USB串口输入，也可离线导入二进制；具体连接和设备可用性需按最终实物情况确认，当前不操作硬件。

已有二进制记录可明确指定模式换算，例如：

```powershell
python -X utf8 host/check_stage6_captures.py --input-bin .\build\my_filtered_capture\capture.bin --source-mode filtered --output .\build\my_filtered_scaled
```

该命令保存原尺度CSV和来源元数据；输出目录有同名成果时拒绝覆盖。它只解码、按指定模式还原计数，不自动认定板测通过，也不从PC接收分块时间推算实际采样率。长间断超过SEQ一整圈时不能仅凭SEQ唯一恢复丢失数量。

第七阶段再完成全部历史自检、失败案例回归、最终源码重建和从干净启动的实物复现。传感器初始化回读、校准与实际采样均匀性仍独立验收。
