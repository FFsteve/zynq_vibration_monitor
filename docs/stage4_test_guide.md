# 第四阶段：运行、复查与波形查看

更新日期：2026-10-31。四个新增RTL模块已有自检，ModelSim与Vivado XSim已实际运行。结论和范围见 [第四阶段实现验证](../report/stage4_validation.md)。本阶段不要求下载新比特流，现有板级top仍执行原始数据回传。

## 一键运行

在项目根目录的PowerShell执行：

```powershell
Set-Location D:\Code\zynq_vibration_monitor
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage4.ps1 -Simulator both
```

脚本依次生成独立数值向量、检查系数SHA256，在两个仿真器上运行 `dc_remove`、`fir_lp_serial`、`vibration_filter`、`filter_monitor_core`，随后检查RTL导出结果和频率增益，并运行缺失系数/非法断流阈值的负向用例。每次先将当前结果标为NOT_RUN；任何编译、评分或证据检查失败都会中止，不沿用旧PASS。

默认工具为 `D:\modelsim\win64`、`D:\Xilinx\Vivado\2020.2\bin`；Python默认使用本机带NumPy的Codex运行时。需要换路径时使用 `-ModelSimBin`、`-VivadoBin`、`-PythonExe` 参数。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage4.ps1 -Simulator modelsim -Test fir_lp_serial
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\run_stage4.ps1 -Simulator xsim -Test vibration_filter
```

单项运行只执行所选模块，不声称重新完成整个阶段。完整导出检查需两种数值测试的结果都存在：

```powershell
& 'C:\Users\QQ165\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -X utf8 .\host\check_stage4_captures.py
```

负向用例也可单独执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\sim\check_stage4_negative.ps1 -Simulator both
```

负向测试中看到 `ERROR fir coefficients missing` 或 `ERROR filter gap must exceed latency` 是预期拒绝；只有对应结果文件为 `PASS negative ...`、且未产生意外接纳哨兵，才算测试通过。正常模块测试出现ERROR则应排查。

## 应看到的结果

| 模块 | 主要检查 | 正常结果 |
|---|---|---|
| dc_remove | 41728组输入、极值、正负半单位、暂停/重启/复位 | 对应结果文件PASS、errors=0 |
| fir_lp_serial | 41728组卷积、环形历史、190拍、保持请求、窄输出饱和、计算阶段复位 | PASS、errors=0；输出逐样本匹配 |
| vibration_filter | 4000组三轴、193拍、SEQ回绕/跳号/重复、过载和断流边界恢复 | PASS、errors=0；三轴同拍、SEQ正确 |
| filter_monitor_core | 600包独立向量、九个截断位置、坏校验/停止位及恢复、默认参数通道 | PASS、errors=0；原始包仍逐字节相同 |

输出目录为 `build/modelsim_stage4/<模块>/` 与 `build/xsim_stage4/<模块>/`。每项有当前结果文本和工具日志；FIR额外写 `rtl_fir.csv`，三轴写 `rtl_triple.csv`，各引擎根目录的 `capture_validation.json` 保存实际RTL频率检查结果。

## ModelSim GUI查看

先执行一键脚本完成编译并准备系数、向量，再在ModelSim的Transcript中执行以下命令。这里不调用会退出GUI的批处理do文件：

```tcl
cd D:/Code/zynq_vibration_monitor/build/modelsim_stage4/vibration_filter
vmap work D:/Code/zynq_vibration_monitor/build/modelsim_stage4/vibration_filter/work
vsim -onfinish stop -voptargs=+acc work.tb_vibration_filter
add wave sim:/tb_vibration_filter/input_valid
add wave sim:/tb_vibration_filter/ready
add wave sim:/tb_vibration_filter/seq
add wave sim:/tb_vibration_filter/result_seq
add wave sim:/tb_vibration_filter/ov
add wave -radix signed sim:/tb_vibration_filter/ox sim:/tb_vibration_filter/oy sim:/tb_vibration_filter/oz
add wave sim:/tb_vibration_filter/full sim:/tb_vibration_filter/overrun sim:/tb_vibration_filter/restarted
run -all
```

需要看内部计算时，可从Instances/Objects加入 `dut/ux/baseline_q`、`dut/fxu/state`、`tap`、`sample_reg`、`coefficient_reg`、`product_reg`、`accumulator`。不要只看无符号十六进制解释负数，数据使用signed decimal。信号若被优化，可保持 `-voptargs=+acc` 并重新加载。

## Vivado XSim GUI查看

使用一键脚本生成的独立快照，避免修改现有板级Vivado工程：

```powershell
Set-Location D:\Code\zynq_vibration_monitor\build\xsim_stage4\vibration_filter
& 'D:\Xilinx\Vivado\2020.2\bin\xsim.bat' stage4_vibration_filter -gui -onfinish stop
```

在XSim的Scopes/Objects中选择 `tb_vibration_filter`，将上表相关输入、ready、SEQ、输出valid及三轴加入Wave，运行到结束。其它模块将目录和快照名替换为对应模块。系数文件和向量依赖当前工作目录，不要只把TB拷到其它目录运行。

若另建Vivado仿真工程，新增RTL仅为Verilog Design Sources，TB及 `stage4_check.vh` 放Simulation Sources；设置正确的仿真顶层，并显式准备运行目录的系数与向量。本指南推荐直接复用脚本快照，避免手工遗漏依赖。

## 隔离综合和内部时序

```powershell
Set-Location D:\Code\zynq_vibration_monitor
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_stage4_synthesis.ps1
```

脚本对 `vibration_filter` 做OOC综合、布局布线和资源检查；时钟20ns，严格检查同一时钟内部寄存器的建立/保持路径，不增加false_path。没有父级数据路径，不虚构端口输入输出时序；端口边界留待最终系统集成。结果见 `build/stage4_synthesis/` 的资源、内部setup/hold、全局时序和DRC报告。

目前仍有3条DPOP-1与1条ZPS7-1 Warning，以及OOC时钟父级位置提示；不是零警告或板级时序签核。脚本不读写原工程缓存，不生成比特流、不连接Hardware Manager、不烧录。

## 如何判断当前阶段完成

两个仿真器的四项自检通过，数值导出逐样本匹配且频率目标满足，负向参数用例被正确拒绝，新增计算模块资源与内部时序有实际证据，即完成本阶段软件验收。

FIR的190拍及三轴193拍是计算延迟；31样本/124ms是FIR信号群延迟，不能混淆。`history_full_o`只说明已有63个连续有效样本，不表示传感器已校准或所有动态直流分量已消退。

上板、传感器初始化回读、静态校准、真实采样稳定性和滤波效果保留到最终联调。现在观察原始回传D1时，仍应与D0相同，不能期待它已变成18位滤波结果。
