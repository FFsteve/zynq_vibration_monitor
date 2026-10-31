# 第七阶段交付与复现入口

本阶段完成全量软件回归、失败修正、最终源码重建、原始/滤波/ILA三版下载文件和候选版本冻结；实际证据见 [第七阶段报告](../report/stage7_validation.md)。新增完整功能尚未上板，下一步按 [上板测试方案](board_test_plan.md) 填写 [实物记录](../report/final_board_record.md)。

## 最短操作路径

1. 打开 `build/release/v1.0-rc1/`，先看release_manifest.json和source_manifest.json。
2. STM32先使用FixedSource；FPGA先下载fpga/raw/system.bit，完成固定包逐字节对照。
3. FPGA更换filtered版，FixedSource三轴回包应为0；再进行SensorSource原始/滤波测试。
4. 需要观察窗口、RMS和报警时，使用fpga/debug配对的system.bit/system.ltx，按照probe_map.tsv设触发。
5. 严格数字频率/报警验收使用board_vectors和host/board_test.py，先完成USB-TTL隔离接线；不具备设备时将该项标为待验证。

不要直接在旧本地Vivado工程点击生成并下载旧top后期待新增功能。本轮使用system_top独立构建；没有更改原工程或对硬件执行下载。原始版回传尺度1，滤波和debug版回传尺度4，包内没有模式字段。

## 软件环境

- Windows PowerShell 5.1或兼容版本；中文说明的ps1使用UTF-8 BOM。
- ModelSim SE64 2020.4、Vivado/XSim 2020.2，项目脚本可覆盖安装路径。
- Python3.12，本机NumPy2.3.5；在线串口另需pyserial。可以在自选虚拟环境执行 `python -m pip install -r host/requirements.txt`，不要求修改全局Python。
- Keil ARM Compiler5.06 update7，STM32F10x标准库沿用本地 `stm32/Libraries`；GCC仅用于可移植应用自检，不代替Keil固件。
- skill官方结构验证使用的PyYAML6.0.3只放在build/stage7_tools，不是项目运行时依赖。

## 一键重跑与生成

从仓库根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_stage7.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_release.ps1
python -X utf8 host/board_test.py generate --output build/stage7_board_vectors
python -X utf8 scripts/package_release.py --version v1.0-rc2
```

第一条默认运行ModelSim/XSim全部阶段、PC单元和捕获检查、可移植C与C/Python对照、两个Keil目标全量重建。支持-PythonExe/-ModelSimBin/-VivadoBin/-UV4/-Gcc；三种发布构建支持-VivadoBin。第三、四条使用安装了NumPy的Python。

候选v1.0-rc1已冻结后，打包器拒绝覆盖同版本，示例使用rc2。只有回归结果全部为PASS、下载构建和报告存在才打包；不能通过改结果文件替代实际执行。重新生成只是软件构建，不调用Hardware Manager、program_hw_devices、真实COM或Flash下载。

## 候选包内容

| 路径 | 内容 |
|---|---|
| fpga/raw、filtered | 普通两模式bit、DCP、资源/时序/DRC/CDC及分支检查 |
| fpga/debug | ILA调试bit、匹配ltx、探针映射及独立资源时序报告 |
| stm32/FixedSource、SensorSource | 最终AXF、HEX和Keil日志 |
| board_vectors | 固定、8个频点和报警周期的数字激励、预期回包和窗口CSV |
| validation | 最终回归日志、机器结果及实际RTL样本对照 |
| source.zip、source_manifest.json | 自有源码、文档及SHA256，不含厂商库/PDF/生成IP源 |
| release_manifest.json | 下载与归档文件哈希、版本、已知边界 |

源码包里的项目技能是skill/fir-validation；没有自动安装。固件可直接用提供文件进行原有流程下载，重新编译源码时仍需本地Libraries及工具链，不能把缺少有版权的厂商库说成源包可无依赖重建。

## 冻结与签收边界

v1.0-rc1表示软件验证候选版，不表示实物已验收或工业故障检测产品。正式板测后才决定是否签收或产生rc2；任何修复都重新记录源码/下载文件哈希和受影响测试。

FPGA JTAG配置掉电不保留，重新上电需要再次配置；本轮不制作PS/FSBL/QSPI/SD启动系统。STM32内部Flash程序可掉电保存。没有新LED/复位引脚，当前内部状态通过ILA观测。

完整性判断和未完成实物项见 [需求核对](../report/requirements_audit.md)。原始硬件PDF、用户标准库及厂商IP生成源未随自有源码包分发；本轮没有公开上传或推送仓库。
