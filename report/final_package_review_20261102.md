# 蜂鸣器最终工程包核查

日期：2026-11-02。版本：v1.0-buzzer-20261102。设计报告按用户要求后续完成，本次不将其算作已交。

## 交付身份与目录

当前版本已提交并推送 origin/main，主功能提交为 af8a7c9b83dda1e1df713bafb64f417f3cf60a8d，远端实际查询相同。之后的提交只补充本核查与验证记录，不改变功能 RTL。

独立工程包位于 D:/Code/zynq_vibration_monitor/zynq_vibration_monitor_final。它不引用原 vivado_project 或缓存；保留 rtl/stm32/host/sim/constr/scripts/data/docs/report/skill/board 等自定义布局，根 README.md 映射竞赛推荐结构。skill/README.md 单独负责技能说明。

包初次生成 524 个清单文件，其中包含 88 个本地第三方依赖文件，约 21.94 MB；补入本核查 Markdown/JSON 后为 526 个清单文件，最终以 package_manifest.json 为准。运行验证产生的 build 结果另归档到原工作区 build/final_verification，不作为必要源码反复打包。源码与小体积证据已同步 GitHub，本地工程包自身被忽略，避免递归重复提交第三方依赖；公开仓库可按 scripts/package_final.py 重新组包。

## 对照用户图片的要求

| 要求 | 当前落实 | 状态 |
|---|---|---|
| 完整项目与自有源代码 | 20 份 RTL、21 个自检顶层、STM32应用/BSP/config/Keil工程、主机参考/采集、MEM/XDC和脚本；不是只提供bit | 完成 |
| 仿真或验证结果及判定依据 | 原双工具全阶段报告/日志、蜂鸣器双工具原始记录；本轮从独立包再次实际运行XSim两项 | 完成 |
| 综合实现资源/时钟/关键指标 | board/fpga/debug/原Vivado2020.2资源、时序、DRC、CDC、IO报告；50MHz，7.377/0.020ns，6625LUT/11521FF/6DSP/12BRAM，8项DRC Warning保留 | 完成，非本轮重新实现 |
| 上板工程、运行入口、实测/参考比对 | 新顶层与源码构建脚本、配对bit/ltx/校准HEX、下载说明、真实UART无损原件与逐帧比对CSV、ILA CSV和三状态原图 | 完成 |
| 可复现构建脚本 | build_buzzer.ps1/.tcl、run_buzzer.ps1、build_keil.ps1与明确工具路径参数；不依赖旧xpr | 完成 |
| Skill含适用/用法/失效/效果来源 | skill/README.md独立于工程README，主技能覆盖全流程、FIR专项保留，附触发式排错清单、提示词、案例和可配置校验脚本 | 完成 |
| 提取整个协作过程 | 旧聊天46轮、当前聊天37轮读取至本轮截点；保存对外正文、重要纠错日志和跨阶段经验，附件/工具/内部推理不导出 | 完成，说明读取边界 |
| 可供陌生题目使用 | 主技能不锁定本项目引脚/阈值，案例常数单独列出；CSV脚本用其他列名测试正常、错误、空/缺列、恢复 | 完成，未声称异板完整流程实测 |
| README说明目录选择 | 根README给出原结构→推荐结构映射，文件名ASCII，中文写在内容中 | 完成 |
| MIT开源 | 根LICENSE、自有代码MIT；第三方声明与依赖锁定，库和未核授权PDF不公开 | 完成 |
| 明确Vivado版本 | 根README、复现指南、board README、机器清单均写明2020.2 | 完成 |
| 最终设计报告 | 本轮用户明确安排后续完成；阶段设计/验证文档继续随包 | 本次范围之外，尚未完成 |

## 本次实际执行

以下命令在独立包根目录或用脚本参数明确指向该目录运行，工具安装路径使用本机实际值：

```powershell
python -X utf8 scripts/verify_delivery.py --root . --require-vendor
python -X utf8 scripts/replay_delivery.py
python -X utf8 -m unittest discover -s host -p "test_*.py" -v
python -X utf8 skill/pl-sensor-workflow/scripts/check_csv.py --self-test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File sim/run_buzzer.ps1 -Simulator xsim
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/build_keil.ps1 -Target SensorCalibratedTrial
```

| 实际检查 | 结果 |
|---|---|
| 源文件/下载文件清单、88个依赖指纹 | 全部相符；20个RTL均有对应TB |
| 独立包XSim模块 | PASS alarm_buzzer checks=42 errors=0 |
| 独立包XSim新旧顶层 | PASS system_buzzer_top checks=12732334 errors=0 |
| 独立包Keil全量重建 | 0 Error(s), 0 Warning(s)；重新生成HEX与board交付HEX SHA256完全相同 |
| 独立包真实滤波重放 | 4915输入、4914完整回复，三轴不匹配0；末尾6字节截断单列 |
| 独立包主机自检 | 11项全部通过；测试中故意构造的FAIL输出不是最终失败 |
| Skill CSV脚本 | 本案例4914行通过；异列名正常、4个拒绝反例及恢复通过 |
| Skill结构校验 | 主技能和FIR专项均通过官方quick_validate；不称独立行为评测 |
| 依赖导入入口 | prepare_vendor.py实际验证并原样导入88文件，随后包清单核验通过 |
| 校验器反例 | 篡改内容、越界路径均拒绝，恢复原内容后通过 |
| 提交检查 | 暂存字节与原文件相同，ASCII无空格路径，无所查秘密模式，排除原始长采样/厂商源码/原PDF/缓存 |

原机器记录：delivery_validation_20261102.json；本包执行记录：final_package_review_20261102.json；详细新工具日志在原工作区 build/final_verification/。首次系统临时目录不可写、技能校验缺PyYAML，分别通过本进程TEMP/TMP和既有build/stage7_tools重试解决，没有改变功能代码或系统策略。

## 保留限制

本次未重跑全部七阶段或重新进行Vivado布局布线；这些已有真实记录，当前功能源文件和下载身份已经核对。新目录额外执行了受路径迁移影响的XSim、Keil及数据重放检查。最终蜂鸣器上板通过来自用户确认，没有新增录音或助手操作板卡。

实际约250.5Hz及周期性短间隔、无受控机械源频响/工业故障分类等限制不因打包消失。厂商库在本地包保留原许可，公开Git需要合法准备该外部依赖，不能称为无外部依赖。最终设计报告、视频及其他报名材料未在此轮虚报完成。
