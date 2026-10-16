# CANDIDATE ONLY: check XC7Z010 package, VCCO, oscillator and baseboard rev BEFORE implementation/connection.
# RTL top must expose clk, pl_rx, pl_tx with exact names.
set_property PACKAGE_PIN U13 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -name pl_clk_50m -period 20.000 [get_ports clk]
set_property PACKAGE_PIN K14 [get_ports pl_rx]
set_property IOSTANDARD LVCMOS33 [get_ports pl_rx]
set_property PACKAGE_PIN M15 [get_ports pl_tx]
set_property IOSTANDARD LVCMOS33 [get_ports pl_tx]
# Add verified reset pin only after tracing core/baseboard nets. Do not invent a PACKAGE_PIN.
