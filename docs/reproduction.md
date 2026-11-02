# 当前蜂鸣器工程的复现步骤

## 入口与依赖

在克隆仓库或独立工程包的根目录操作，所有相对路径保持不变。**Vivado 2020.2**、xc7z010clg400-1 器件支持、Keil ARM Compiler 5.06 update 7 为已验证环境。ModelSim 2020.4 是第二工具；Python 3.12/NumPy 2.3.5 用于参考，pyserial 只用于真实串口。

本地工程包已经含当前 stm32/Libraries 原文件。公开 Git 为遵守第三方许可边界不提供该目录。从合法持有的同版资料目录导入：

```powershell
python -X utf8 scripts/prepare_vendor.py --source "E:\your_stm32_libraries" --root .
python -X utf8 scripts/verify_delivery.py --root . --require-vendor
```

source 指向含 CMSIS/、STM32F10x_StdPeriph_Driver/ 的目录。脚本先逐文件核验 stm32/vendor_manifest.json；版本不同必须明确报告并重新验证，不能把名称相同当成字节相同。不得用 HAL 替换。

工具目录用参数覆盖。示例脚本的 D: 默认只是本机安装路径，不是项目必须放在 D: 的要求。可先用 `python -m pip install -r host/requirements.txt` 安装主机依赖。

## 仿真、固件和 FPGA

```powershell
python -X utf8 -m unittest discover -s host -p "test_*.py" -v
powershell.exe -NoProfile -ExecutionPolicy Bypass -File sim/run_buzzer.ps1 -Simulator both -ModelSimBin "D:\modelsim\win64" -VivadoBin "D:\Xilinx\Vivado\2020.2\bin"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/test_calibration.ps1 -Python python -Gcc "D:\msys2\ucrt64\bin\gcc.exe"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/build_keil.ps1 -Target SensorCalibratedTrial -UV4 "D:\Keil_v5\Main_Program\UV4\UV4.exe" -FromElf "D:\Keil_v5\Main_Program\ARM\ARMCC\bin\fromelf.exe"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build_buzzer.ps1 -VivadoBin "D:\Xilinx\Vivado\2020.2\bin"
```

sim/run_buzzer.ps1 -Simulator xsim 可仅使用随 Vivado 的仿真器。完整历史阶段重新验证入口为 scripts/run_stage7.ps1，需指定本机 PythonExe、Gcc、UV4、ModelSimBin、VivadoBin；它覆盖原七阶段，不包含后加校准与蜂鸣器，后两者必须执行上面的专项入口。全量重跑不是使用已验证下载文件的必要步骤。

构建从 RTL、MEM 和 XDC 在内存工程完成综合、布局布线、插入 ILA、报告与 bit/ltx 生成，不要求原 xpr 或缓存。顶层 system_buzzer_top，RETURN_FILTERED=1。系数文件 SHA256 会检查，缺失或变更将拒绝构建。实现阶段才读取 system_uart_rx_cdc.xdc。

build/ 是本次运行输出，board/ 是交付时的历史下载与报告；重新构建后不能用 board/ 的旧 PASS 冒充本次执行结果。重新生成 bit 可能因工具/映射差异有不同哈希，必须检查本次资源、时序、DRC，并保存自己的配对 ltx。

## 下载与演示

1. 按 docs/wiring_guide.md 与 hardware_pinmap.md 核对相同板型；使用 TTL 3.3V、共地，隔离原 COM2 接收驱动。未测电压仍应由操作者确认。
2. STM32 使用 SensorCalibratedTrial 校准 HEX；该参数只适用于当前模块，同型号另一颗传感器不能直接认定校准有效。
3. Vivado 2020.2 Hardware Manager 打开目标；Program Device 同时选同一目录的 system.bit、system.ltx。硬件列表 hw_ila_1 对应 stage7_ila，不能拿 filtered 普通版 bit 配 ILA ltx。
4. 静止待预热和有效窗口，观察 quality/alarm_valid=1、alarm_axes=0；移动使任一轴连续两窗超过置位门限时，蜂鸣器发声；放稳连续两窗低于解除门限后停止。阈值为原型演示值。
5. 需要数值取证时触发 feature_valid=1，保存完整 ILA CSV 和截图；同时采 D0 输入/D1 输出时记录启动与复位顺序、时间对应和回传尺度。1024 点在 50 MHz 连续采样只覆盖 20.48 μs，不是完整 128 样本窗时长。
6. FPGA JTAG 配置断电丢失；重新上电需再次下载。本工程未制作 PS/FSBL/QSPI/SD 启动镜像。

## 复现判定与故障

最小判定为：文件校验通过，所选环境构建通过，同版配对文件可下载，原 UART/ILA 继续更新，静止不响、有效报警响、解除停止。模块/协议修改后应运行对应正常、错误和恢复自检。

遇到问题按 skill/pl-sensor-workflow/references/pitfalls.md 分层定位。脚本执行策略只影响 PowerShell 启动；DLL 重定位或工具安装目录访问失败只说明工具未运行，不能先改 RTL 或关闭系统安全设置。坏包、断流和截断后的恢复由自检覆盖，物理长时间抗扰与工业故障分类不在本次签收范围。

