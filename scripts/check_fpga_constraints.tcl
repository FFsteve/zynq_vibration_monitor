# 在隔离的 build 目录运行，不打开用户现有 Vivado 工程或连接硬件。
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set output_dir [file join $repo_root build fpga_constraints_check]
file mkdir $output_dir
cd $output_dir
set result_file [file join $output_dir constraints_result.txt]
set f [open $result_file w]; puts $f "NOT_RUN"; close $f
create_project -in_memory -part xc7z010clg400-1
set_property target_language Verilog [current_project]
foreach module {uart_rx uart_tx packet_parser power_on_reset return_controller monitor_core top} {
    read_verilog [file join $repo_root rtl ${module}.v]
}
read_xdc [file join $repo_root constr top.xdc]
synth_design -top top -part xc7z010clg400-1
if {[llength [get_pins -quiet u_core/u_rx/rx_meta_reg/D]] != 1} {error "Missing UART RX first-stage D pin"}
read_xdc [file join $repo_root constr uart_rx_cdc.xdc]

# 检查对象存在且无缺失端口，避免 get_ports 拼写错误产生空约束。
if {[llength [get_ports]] != 3} {error "Expected three top ports"}
foreach {port_name package_pin bank} {clk U18 34 pl_rx K14 35 pl_tx M15 35} {
    set p [get_ports $port_name]
    if {[llength $p] != 1} {error "Missing port: $port_name"}
    if {[get_property PACKAGE_PIN $p] ne $package_pin} {error "Incorrect pin: $port_name"}
    if {[get_property IOSTANDARD $p] ne "LVCMOS33"} {error "Incorrect IOSTANDARD: $port_name"}
    if {[get_property BANK [get_package_pins $package_pin]] ne $bank} {error "Incorrect bank: $port_name"}
}
set c [get_clocks pl_clk_50m]
if {[llength $c] != 1 || [get_property PERIOD $c] != 20.000} {error "Incorrect 50 MHz clock"}
foreach reg_name {rx_meta_reg rx_sync_reg} {
    set cell [get_cells u_core/u_rx/$reg_name]
    if {[llength $cell] != 1 || ![get_property ASYNC_REG $cell]} {error "Missing synchronizer: $reg_name"}
}

opt_design
place_design
route_design
report_io -file io.rpt
report_clocks -file clocks.rpt
report_exceptions -file exceptions.rpt
report_timing_summary -report_unconstrained -file timing_summary.rpt
report_utilization -file utilization.rpt
report_drc -file drc.rpt
report_cdc -details -file cdc.rpt

# 两级同步寄存器之间必须仍有受约束路径，不能被宽泛的 false_path 隐藏。
set sync_path [get_timing_paths -from [get_pins u_core/u_rx/rx_meta_reg/Q] -to [get_pins u_core/u_rx/rx_sync_reg/D] -max_paths 1]
if {[llength $sync_path] != 1} {error "Synchronizer internal timing path was lost"}
report_timing -of_objects $sync_path -file rx_sync_timing.rpt
set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup_paths] != 1 || [llength $hold_paths] != 1} {error "Missing internal timing paths"}
set setup_slack [get_property SLACK $setup_paths]
set hold_slack [get_property SLACK $hold_paths]
if {$setup_slack < 0 || $hold_slack < 0} {error "Timing failed: setup=$setup_slack hold=$hold_slack"}
set violations [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]
if {[llength $violations]} {error "DRC has errors or critical warnings: $violations"}
write_checkpoint -force routed_top.dcp
set f [open $result_file w]
puts $f "PASS constraints part=xc7z010clg400-1 ports=3 setup_slack=$setup_slack hold_slack=$hold_slack"
close $f
puts "PASS FPGA constraints: setup=$setup_slack hold=$hold_slack"
# 本脚本不运行 write_bitstream、Hardware Manager、下载或烧录。
close_project
