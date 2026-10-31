# 第五阶段仿真操作指南

## 自动运行

在仓库根目录打开PowerShell，执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage5.ps1 -Simulator both
```

`Bypass`只作用于本次子进程，不需要修改系统执行策略。ModelSim与XSim是两个不同仿真器，XSim随Vivado提供。默认工具路径为 `D:\modelsim\win64`、`D:\Xilinx\Vivado\2020.2\bin`；Python默认使用本机Codex运行时，向量生成还需要NumPy。其他机器可传 `-ModelSimBin`、`-VivadoBin`、`-PythonExe`。

单项运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage5.ps1 -Simulator modelsim -Test window_features
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage5.ps1 -Simulator xsim -Test feature_monitor_core
```

`-Test`另可选 `isqrt_u36`、`threshold_alarm`。默认 `all` 在四项完成后追加整批导出对照和八项非法参数测试；单模块通过不代表整阶段验收。

脚本先运行独立参考和向量生成、核对滤波系数哈希，再在 `build/modelsim_stage5/`、`build/xsim_stage5/` 独立编译和仿真。不会连接开发板、烧录或修改本地Vivado工程。

## 通过标准与覆盖

四个主测试必须输出 `PASS <模块> checks=<数量> errors=0`。脚本同时检查进程退出码、TB完成标志、错误计数及当前结果文件。非法参数测试预期出现 `ERROR stage5 invalid ... parameter`，同时不能到达 `UNEXPECTED_ACCEPT` 哨兵；这是主动拒绝的通过条件。

实际RTL导出 `window_capture.txt`、`alarm_capture.txt`、`feature_link_capture.txt`，随后由Python逐项与独立参考对照，两套工具各保存 `capture_summary.json`。

覆盖10033个开方输入、109个默认128样本窗口、5008拍报警激励、1600个合成振动包与12个精确窗口，以及600个错误/失序/复位后恢复包。另测窗长1/2/4/1024、确认数1/255、最大阈值、质量标志注入及发布边界取消。详细标准见 [测试计划](stage5_test_plan.md)，实际结果见 [实现验收记录](../report/stage5_validation.md)。

串口集成主通道压缩时间50倍，UART每位10拍、每包约4000拍；旁路冒烟通道实际使用50MHz、115200、434拍/位，发送3包。压缩仿真不能代表实物采样稳定性；完整250Hz实物验证留待最终联调。

## 查看波形

ModelSim在各测试目录保留 `vsim.wlf`，可通过 `File -> Open` 打开，也可在该测试目录执行：

```powershell
& 'D:\modelsim\win64\vsim.exe' -view .\vsim.wlf
```

XSim在各测试目录保留 `stage5_<模块>.wdb`，可通过Vivado的 `File -> Simulation Waveform -> Open` 打开，或在对应目录执行：

```powershell
& 'D:\Xilinx\Vivado\2020.2\bin\xsim.bat' -gui .\stage5_window_features.wdb
```

观察新窗口有效脉冲、三轴MS/RMS/峰值、首末SEQ、window_id、alarm_axes及alarm_valid。`feature_valid_o`表示新窗口到达；`alarm_valid_o`表示当前报警状态可用。质量无效时的alarm=0不能解释为振动正常。

开方接纳后18拍输出，窗口末样本接纳后22拍输出。从解析器原始帧脉冲至对齐特征实际为218拍，即50MHz下4.36us；此前设计文本的217拍已按集成自检纠正。

## 隔离综合和内部时序

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_stage5_synthesis.ps1
```

以 `feature_monitor_core` 为OOC顶层，包含通信、滤波、窗口和报警，沿用器件 `xc7z010clg400-1`。报告位于 `build/stage5_synthesis/`；目标20ns，只验收该时钟的全部内部寄存器路径。

没有父级数据路径时不虚构端口延迟。接口、父级时钟、异步UART完整约束和最终板级时序仍待整体集成；此项不是板级签核，不生成下载成果。工具警告在实际报告中列出。

## 最终实物联调保留项

新结果尚未接入原板级top或结果串口协议，D1仍为原始回包。最终阶段再合并顶层、确认结果传输、整体时序与板测。传感器零偏/配置回读、真实采样均匀性及实际报警阈值仍待实测，2000/1500只是演示计数阈值。
