# Vivado 工程的 CDC 与 FIR 系数加载警告修正

## 原因

`Vivado 12-4739` 表示 `set_false_path` 没有找到指定的目标引脚。它不能作为有效时序例外使用，也不能仅通过隐藏消息解决。

本次检查磁盘上的 `vivado_project/zynq_vibration_monitor.xpr`，发现：

- 设计顶层保存为旧的 `top`。
- `system_uart_rx_cdc.xdc` 同时用于综合和实现，而它本来只应在综合后的网表上使用。
- 新旧两份 CDC 文件都处于启用状态。

旧顶层的接收器路径为 `u_core/u_rx`；完整系统 `system_top` 的路径为 `u_core/u_processing/filtering/communication/u_rx`。报错中的目标使用完整系统的路径，在旧顶层中找不到。即使选择正确顶层，也应保留 CDC 文件仅用于实现的原定配置，避免在 RTL 展开阶段依赖综合后寄存器引脚名称。

上述顶层结论来自磁盘工程；如果 GUI 中有尚未保存的修改，应以 GUI 当前 `sources_1` 的实际设置为准。发布构建脚本在综合后显式读取相应 CDC 文件，与本次 GUI 工程配置问题不同。

## 完整系统工程的修正操作

1. 在 Vivado 中关闭当前已展开的设计，回到工程界面。
2. 在下方 **Tcl Console** 中执行：

   ```tcl
   set vibration_top system_top
   source D:/Code/zynq_vibration_monitor/scripts/configure_project_cdc.tcl
   ```

3. 确认控制台输出 `PASS project_cdc top=system_top`。在 Sources 中确认 `system_top` 为设计顶层。
4. 重新执行 **Open Elaborated Design**。已经打开的网表不会因为修改文件属性自动重载。
5. 后续重新执行综合、实现；不要继续使用旧顶层的过期运行结果。

脚本设置顶层和两份 CDC 文件的启用状态、综合/实现适用阶段；选择 `system_top` 时，还会将既有 FIR 系数登记为工程源文件。它不改 RTL、引脚、系数内容或下载设置，不执行综合或硬件操作。

完整系统应得到下表的配置；也可在 Sources 中选中文件，在 **Source File Properties** 中手工调整。

| 约束文件 | 是否启用 | 用于综合 | 用于实现 |
| --- | --- | --- | --- |
| `top.xdc` | 是 | 是 | 是 |
| `uart_rx_cdc.xdc` | 否 | 否 | 否 |
| `system_uart_rx_cdc.xdc` | 是 | 否 | 是 |

若专门回测旧通信顶层，将命令第一行改为 `set vibration_top top`。脚本会改用 `uart_rx_cdc.xdc` 并禁用完整系统 CDC 文件。不要将新旧两份同时启用，也不要把两个文件的路径都改成同一个路径。

## 验收与证据

本次隔离检查使用 Vivado 2020.2，不打开或改写正在使用的 `.xpr`。命令为：

```powershell
& 'D:\Xilinx\Vivado\2020.2\bin\vivado.bat' -mode batch -source scripts/check_project_cdc.tcl -log build/project_cdc_check/vivado.log -journal build/project_cdc_check/vivado.jou
```

检查分为三个部分：

1. 使用旧顶层及误启用的完整系统 CDC，重现原 `12-508` / `12-4739` 警告；这是故意保留的错误配置对照。
2. 分别选择 `top` 和 `system_top`，应用修正脚本，检查文件属性并展开设计；修正区间不应再出现上述警告。
3. 分别实际综合两种顶层，精确查询第一级 `rx_meta_reg/D`，要求各命中一个对象；读取匹配的 CDC 文件后，要求第一级 Q 到第二级 `rx_sync_reg/D` 仍能取得正常时序路径，避免豁免整个同步链。

结果入口为 `build/project_cdc_check/result.txt`；时序和例外证据为同目录的 `top_sync_timing.rpt`、`system_top_sync_timing.rpt`、`top_exceptions.rpt`、`system_top_exceptions.rpt`。原错误对照产生的警告与修正后的检查应分开阅读。

2026-10-31 实际执行结果为两种顶层全部通过：错误对照复现原警告，修正后的两个展开区间均无 `12-508` / `12-4739`；两种综合网表各命中一个第一级 D 引脚，第二级仍正常计时。手动重新读取已登记的 XDC 会出现 `filemgmt 56-128` 提示文件不会重复加入工程，随后约束解析正常完成；不将此日志宣称为全程零警告。

此检查针对约束加载与对象匹配，不代替新一次布局布线或上板验收。原冻结发布包保持不变。

## FIR 系数缺失警告的补充修正

后续用户报告 `Synth 8-4445`：无法打开 `fir_lp_63_q16.mem`。实际核查发现，原系数位于 `data/reference/stage4/fir_lp_63_q16.mem`，文件存在且可读，但 GUI 工程没有登记它。RTL 默认参数仅写文件名，不能假定 Vivado 会递归搜索整个仓库。

此前 CDC 隔离检查先把系数复制到了运行目录，因此该检查只覆盖了 CDC，不覆盖 GUI 工程的资源登记完整性。这是检查范围的遗漏，不能据此前结果宣称 GUI 工程资源已经齐全。

现在 `configure_project_cdc.tcl` 已补充资源登记。关闭已展开的设计，重新执行本文的两行配置命令即可。预期先出现 `PASS project_memory`，其中 `words=63`、`type=Memory File`，随后出现原有的 `PASS project_cdc`。脚本重复执行不会重复添加源文件；若存在不同目录下的同名系数则中止并提示冲突。

手工操作时，在 **Add Sources → Add or create design sources** 中添加：

```text
D:/Code/zynq_vibration_monitor/data/reference/stage4/fir_lp_63_q16.mem
```

确认文件类型为 **Memory File**，用于综合和仿真。该文件是计算所需的系数数据，不是 Verilog 源码，也不是 XDC。添加后重新展开设计、重新综合。产生过缺系数警告的综合结果不能作为 FIR 功能验收依据。

新增隔离验证命令：

```powershell
& 'D:\Xilinx\Vivado\2020.2\bin\vivado.bat' -mode batch -source scripts/check_project_memory.tcl -log build/project_memory_check/vivado.log -journal build/project_memory_check/vivado.jou
```

该验证不复制系数到工作目录：先以未登记的工程复现警告，再重复执行配置脚本检查幂等性，重新展开设计，并通过 `launch_runs synth_1` 实际执行工程模式综合。结果及日志位于 `build/project_memory_check/`。

2026-10-31 实际执行通过：未登记对照复现 `8-4445`；登记后展开设计不再出现 `8-4445` 或 `12-4739`；重复登记后仅一个系数源；实际工程综合完成，日志为 0 Warnings、0 Critical Warnings、0 Errors。综合后完整系统的 UART 第一级同步引脚仍命中一个对象。此结果仅指该隔离工程的综合，不代表用户 GUI 已重跑或已经布局布线、上板。

AMD 对实现专用约束的说明见 [UG903：综合与实现约束文件](https://docs.amd.com/r/2024.1-English/ug903-vivado-using-constraints/Synthesis-and-Implementation-Constraint-Files)；本项目同时在实际使用的 Vivado 2020.2 中验证设置。
