# 第三方材料与许可边界

根目录 LICENSE 的 MIT 授权适用于本项目自行编写的 RTL、STM32 应用/BSP、Testbench、脚本、文档和技能包。它不改变第三方代码、工具、库、硬件图纸及生成 IP 的许可。

| 材料 | 处理方式 |
|---|---|
| stm32/Libraries 的 ST 标准外设库 V3.6.2 | 本地原文件包含 SLA0044 Rev5，不能标成 MIT；公开 Git 不收录，复现时从合法持有的资料中导入并核验依赖清单 |
| CMSIS 设备支持 V3.5.1、ARM CoreSupport V1.30 | 保留各文件版权及原许可；公开 Git 不收录，本地工程包作为独立第三方依赖保存 |
| board/stm32/vibration_monitor.hex | 包含以上库的机器码，仅供对应 STM32 器件运行；随附原 ST 许可和第三方声明，不对其中第三方部分重新授权 |
| Vivado/XSim、ModelSim、Keil、ARM Compiler、器件支持包 | 用户自行安装并取得工具许可，不随源码包提供 |
| ILA/debug hub | 由已安装的 Vivado 2020.2 生成；提供配置脚本和调试下载成果，不分发厂商 IP 源码 |
| 原理图、规格书、竞赛指南 PDF | 授权未核实，保留本地参考，不纳入公开仓库；自行整理的核对说明见 docs/ |

本地 zynq_vibration_monitor_final/stm32/Libraries 的许可文件和头部保持原样，依赖哈希见 stm32/vendor_manifest.json。该目录是为用户当前复现保留的本地依赖副本，不作为本项目 MIT 自有代码公开。再次向第三方分发整个本地目录前，应按其原许可处理；可以公开的自有代码与工程包共享同一套依赖导入入口。

项目自有模块不依赖第三方示例实现，没有将厂商示例换名后纳入 MIT。预编译 FPGA 文件和 STM32 文件的用途与来源见 board/README.md。

