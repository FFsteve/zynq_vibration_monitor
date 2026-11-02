# 当前蜂鸣器交付记录

版本：v1.0-buzzer-20261102。工具：**Vivado/XSim 2020.2**、ModelSim 2020.4、Keil ARM Compiler 5.06 update 7。

## 当前事实

2026-11-02 用户在当前对话明确说明：“已最后一次上板已经测试完。蜂鸣器可以正常响应。”据此将最终蜂鸣器功能记为用户确认通过。没有新增录音、声压测量或助手现场操作；旧 build.json 中 physical_buzzer_tested=false 表示其 2026-11-01 构建时点的事实，不改写历史 JSON。当前确认记录见 board/board_confirmation.json。

FPGA 选 board/fpga/debug/system.bit 与 system.ltx；STM32 选 board/stm32/vibration_monitor.hex（SensorCalibratedTrial，sixface_r1_20261101_validated）。旧 raw/filtered/debug rc1 保留为历史，不作为本次蜂鸣器下载入口。

## 证据索引与边界

| 内容 | 已有结果与文件 |
|---|---|
| 原七阶段 | stage1_validation.md 至 stage7_validation.md；42 次双工具阶段运行、24 项负向拒绝，历史原版结果 |
| 新蜂鸣器 | buzzer_validation_20261101.md；evidence/buzzer_20261101/；42 检查模块及 12732334 检查顶层，双工具均 PASS；新旧 UART/快照逐拍对照 |
| 当前实现 | board/fpga/debug/ 下 utilization、timing_summary、internal_setup/hold、drc、cdc、io、probe_map；7.377/0.020 ns，6625 LUT/11521 FF/6 DSP/12 BRAM；8 项 DRC Warning 保留 |
| 校准 | calibration_firmware_update_20261101.md、sixface_static_pass_20261101.md、mpu6050_calibration_params_20261101.json；独立 r2/r2b 验证，拟合只使用 r1 |
| 真实滤波 | filter_test_3_validation_20261101.md；4914 完整 D1 与实测输入驱动参考精确一致；末尾边界截断单列 |
| 同次 ILA | filter_test_4_validation_20261101.md；静止一窗/移动两窗三轴全部特征精确匹配；部分 D0 采集缺口由 I2C 重建并明确标识 |
| 比赛三状态演练 | competition_rehearsal_validation_20261101.md；evidence/fixed_filter_ila_20261101/filter_test_final/ 三张原图，分别为静止、X 轴报警、有效恢复 |
| 声音实物 | 2026-11-02 用户确认正常响应；与前述数值/波形证据分开表述 |
| AI 协作 | ai_records/old_thread.md、new_thread.md 保存两聊天全部分页的对外正文；ai_devlog.md 记录重要判断与纠错；skill/ 提炼可迁移经验 |

report/evidence/ 中长期完整 ATK 工程与全部 raw CSV 约 1.8GiB，保留原工作区、不上传全部。工程包收录精简的真实 UART 输入/输出、ILA 原始 CSV、三张演练图、独立比对 CSV/JSON 和校准汇总。完整历史数据分析脚本在缺少未收录原文件时不能声称可重跑全历史；本次工程包校验和独立参考回放只针对包内实际数据。

旧阶段报告保留当时“未上板”“实验参数”的历史结论；最新状态以本文件为准。未附受控机械源频响或工业故障数据，不把数值仿真指标当成这些实测结果。设计报告按本次用户要求留后，工程包内容核查不会将其标成已完成。

