# 当前三端口 top 的正式板级约束，适用 xc7z010clg400-1。
# 依据：领航者规格书 V1.2、核心板 2v5、底板 V3.9；详见 docs/fpga_constraints.md。
# 用户确认本板与所给原理图一致；图面额定电压为 3.3V，本轮未实测。

# 50 MHz 单端晶振：X1 -> R7 -> PL_GCLK -> Bank34 的 U18。
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name pl_clk_50m -period 20.000 [get_ports clk]

# STM32 TX -> 底板 J3.1 / UART2_RX -> B35_L20_P -> K14。
set_property -dict {PACKAGE_PIN K14 IOSTANDARD LVCMOS33} [get_ports pl_rx]

# M15 / B35_L23_N -> UART2_TX / 底板 J3.2 -> 外置 USB 串口 RXD。
# 这不是经 P5 跳帽连接的板载 USB/UART3 通道。
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports pl_tx]

# UART 接收端没有与 PL 共享的采样时钟，不虚构同步输出延迟。
# 只排除串行输出端的外部同步时序要求；TX 内部寄存器仍按 50 MHz 检查。
set_false_path -to [get_ports pl_tx]

# 当前 top 没有 sys_rst_n 或 led 端口，不添加示例中的 N16/J16。
# 接收输入的例外在综合后读取 uart_rx_cdc.xdc，只到第一级同步寄存器 D。
