# 自有代码中文注释与一致性核查

日期：2026-11-02。用户要求在原始项目和提交包中添加较详细中文注释，说明程序运行及设计原因。本次仅修改说明性注释，未修改接口、常量、算法、状态转移、协议、校准参数、工具指令或下载设置。

## 修改范围与阅读顺序

- 全部20份rtl/*.v，含通信基线、滤波、开方、窗口、滞回报警、回传选择、完整系统与蜂鸣器顶层。
- stm32/app/的8份应用和头文件、stm32/bsp/的8份驱动和头文件、stm32/config/的2份配置，以及stm32/tests/的2份自有C自检，共20份。
- 新增362行注释，按文件开头说明职责、输入输出、流程和设计原因，再在关键状态/运算/错误出口解释细节；同时纠正两处过时的校准注释。第三方标准库、CMSIS及启动文件保留原样。
- 系统阅读从rtl/system_buzzer_top.v进入system_monitor_core.v；位与包恢复看uart_rx.v和packet_parser.v；滤波看vibration_filter.v、dc_remove.v、fir_lp_serial.v；统计及报警看window_features.v、isqrt_u36.v、threshold_alarm.v。
- STM32从app/main.c进入acquisition.c，随后看bsp/mpu6050.c、bsp_i2c.c、app/accel_calibration.c与sample_packet.c；头文件给出调用限制和返回值约定。

关键说明包括两级同步与位中心采样、滑动窗口及超时边界、事件和握手区别、队列满丢新包、Q16位宽与负数舍入、FIR历史预热及重建、完整连续窗口、MS平方门限与滞回确认、报警有效性和单向蜂鸣器支路、I2C单/双/多字节收尾、短临界区与有界超时、采样调度及失败后的SEQ缺口。

## 实际验证

修改前保存40个文件原字节；修改后使用识别字符串及字符字面量的扫描器去除注释，逐文件比较词法记号、预处理指令行，以及综合工具注释的内容和相对代码位置。结果40/40一致，变化的代码记号为0。同步后原目录与zynq_vibration_monitor_final/中的40份源码逐字节一致。逐文件修改前/后SHA256及记号指纹见同名JSON。

实际运行的检查命令如下。Python使用本次Codex捆绑运行时，传给既有脚本，不新增项目依赖：

```powershell
$pythonPath='C:/Program Files/WindowsApps/OpenAI.CodexPrimaryRuntime.v26-1026-487-0_26.1026.487.0_x64__3k8sg7r9htsxt/dependencies/python/python.exe'
& $pythonPath -X utf8 build/comment_review/verify_comments.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/test_portable.ps1 -Python $pythonPath
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/test_calibration.ps1 -Python $pythonPath
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/build_keil.ps1 -Target both
powershell.exe -NoProfile -ExecutionPolicy Bypass -File stm32/build_keil.ps1 -Target SensorCalibratedTrial
$rtlFiles=@(Get-ChildItem -LiteralPath rtl -Filter *.v | ForEach-Object {$_.FullName})
# XVLOG实际在隔离目录build/comment_review/xvlog内运行。
Push-Location build/comment_review/xvlog
& 'D:/Xilinx/Vivado/2020.2/bin/xvlog.bat' @rtlFiles
Pop-Location
```

结果：XVLOG 2020.2编译全部20模块退出0；可移植编码65536值和32个交叉解码向量通过；校准196608轴值与65536包独立参考、错误恢复和固定源旁路检查通过。Keil三个既有目标分别全量重建，均0错误0警告。校准HEX与已发布文件SHA256仍相同，为895bbfa1f1076716d045b9235c65d62adbddf2c927687b5f0cc3e177c75a41d5。

首次Keil在受限环境中无法CreateProcess启动子编译器，非代码编译诊断；保留build/comment_review/keil_original.txt失败记录，换正常工具环境重试通过。成功日志、XVLOG日志及比较工具/快照保存在build/comment_review/，不纳入必要源码包。未将第一次失败隐去或直接记作通过。

本次不重新执行RTL仿真、Vivado综合实现或板测；注释不改变逻辑，现有bit/ltx及发布HEX保持不变，无需为这些注释重新烧录。没有提交Git或推送GitHub。原有设计报告文件保持不变。

## 提交包同步

40份源码、此核查正文/JSON及ai_devlog已同步到本地zynq_vibration_monitor_final/，package_manifest.json更新对应文件指纹并增加source_comments_update说明。最终继续运行原始目录与提交包的verify_delivery.py，核对全部清单及88个第三方依赖。此前设计报告照片待补状态保持不变。
