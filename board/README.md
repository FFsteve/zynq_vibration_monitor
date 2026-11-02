# 当前上板文件与实现报告

版本 v1.0-buzzer-20261102，**Vivado 2020.2**，xc7z010clg400-1，system_buzzer_top，RETURN_FILTERED=1。本目录是选定的历史生成成果，重建入口为 ../scripts/build_buzzer.ps1，不依赖原 GUI 工程。

| 文件 | 用途 |
|---|---|
| fpga/debug/system.bit | 当前蜂鸣器 + 完整滤波/特征/报警 + ILA 的 FPGA 下载文件 |
| fpga/debug/system.ltx | 同次 ILA 探针文件，必须与上面的 bit 配对 |
| fpga/debug/probe_map.tsv | 21 组427位探针对应；Hardware Manager 的 hw_ila_1 对应 stage7_ila |
| stm32/vibration_monitor.hex | SensorCalibratedTrial，sixface_r1_20261101_validated，保持十字节协议 |
| stm32/keil_build.txt | 该校准目标实际编译记录，0错误/0警告 |
| fpga/debug/*.rpt | 资源、时序、DRC、CDC、IO 的实际 Vivado 报告 |
| validation/ | 原阶段回归与新增蜂鸣器的实际日志，区分生成时点 |
| artifacts.json | 本目录发布文件 SHA256；运行 scripts/verify_delivery.py 校验 |
| board_confirmation.json | 2026-11-02 用户最终蜂鸣器上板确认，与旧构建时未板测状态分开 |
| third_party/ | 固件依赖的原厂许可与版权说明，不适用本项目MIT重新授权 |

STM32 HEX SHA256：895bbfa1f1076716d045b9235c65d62adbddf2c927687b5f0cc3e177c75a41d5。
FPGA bit SHA256：2631a9d1d3e89ccb0ec4de3fe9626d780cc754945f69c6f3dffbdafb57ee7b4b。
配对 ltx SHA256：0d8a495be673a0d07fd5c42eec5ce3d174492d0eeb98affd398f3ce2ebf9efbb。

STM32 不使用原 SensorSource 或早期 short_capture 校准固件作为最终程序。FPGA 不使用旧 raw/filtered bit 配本 ltx。按 ../docs/reproduction.md 下载与演示；文件准备脚本不连接板卡或执行烧录。

当前资源 6625 LUT/11521 FF/6 DSP/12 BRAM（36Kb等效）；50MHz内部建立/保持裕量7.377/0.020ns；保留8项DRC Warning。UART与蜂鸣器外部端点不虚构同步接收预算。原 FPGA JTAG 配置掉电不保留，重上电要重新配置。

