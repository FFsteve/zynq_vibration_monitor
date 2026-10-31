# 独立完成两个模式的板级实现，不打开本地工程或生成下载文件。
set root [file normalize [file join [file dirname [info script]] ..]]
foreach mode {0 1} {
    set label [lindex {raw filtered} $mode]
    set out [file join $root build stage6_implementation $label]
    file mkdir $out
    cd $out
    set result [file join $out implementation_result.txt]
    set f [open $result w];puts $f "NOT_RUN";close $f
    create_project -in_memory -part xc7z010clg400-1
    foreach name {uart_rx uart_tx packet_parser power_on_reset return_controller monitor_core dc_remove fir_lp_serial vibration_filter filter_monitor_core isqrt_u36 window_features threshold_alarm feature_monitor_core return_source_select system_monitor_core system_top} {
        read_verilog [file join $root rtl ${name}.v]
    }
    read_xdc [file join $root constr top.xdc]
    synth_design -top system_top -part xc7z010clg400-1 -generic RETURN_FILTERED=$mode
    read_xdc [file join $root constr system_uart_rx_cdc.xdc]
    foreach {port pin bank} {clk U18 34 pl_rx K14 35 pl_tx M15 35} {
        set object [get_ports $port]
        if {[llength $object]!=1 || [get_property PACKAGE_PIN $object] ne $pin || [get_property IOSTANDARD $object] ne "LVCMOS33"} {error "IO mismatch: $port"}
        if {[get_property BANK [get_package_pins $pin]] ne $bank} {error "Bank mismatch: $port"}
    }
    if {[llength [get_ports]]!=3 || [get_property PERIOD [get_clocks pl_clk_50m]]!=20.000} {error "Top interface or clock mismatch"}
    set prefix u_core/u_processing/filtering/communication/u_rx
    foreach name {rx_meta_reg rx_sync_reg} {
        set object [get_cells $prefix/$name]
        if {[llength $object]!=1 || ![get_property ASYNC_REG $object]} {error "Missing synchronizer $name"}
    }
    # 没有插入ILA时，明确保留被标记的观测网络，不能仅依赖综合阶段KEEP。
    set debug_nets [get_nets -hier -filter {MARK_DEBUG == 1}]
    if {[llength $debug_nets]==0} {error "Missing marked observation networks"}
    set_property DONT_TOUCH true $debug_nets
    set debug_registers [get_cells -hier -filter {NAME =~ debug_* && IS_SEQUENTIAL == 1}]
    if {[llength $debug_registers]<400} {error "Missing physical observation registers"}
    set_property DONT_TOUCH true $debug_registers
    opt_design
    write_checkpoint -force optimized_system.dcp
    report_utilization -hierarchical -file preflight_utilization.rpt
    set cell_file [open optimized_cells.tsv w]
    foreach cell [get_cells -hier] {puts $cell_file "[get_property NAME $cell]\t[get_property REF_NAME $cell]"}
    close $cell_file
    # 两模式都必须保留完整计算分支，旧的无输出发送支路必须被移除。
    set f [open hierarchy_check.txt w]
    foreach pattern {*features/ux/* *features/uy/* *features/uz/* *alarm/* *processing/fxu/* *processing/fyu/* *processing/fzu/*} {
        set objects [get_cells -hier -filter "NAME =~ $pattern"]
        if {[llength $objects]==0} {error "Computation branch missing: $pattern"}
        puts $f "$pattern cells=[llength $objects]"
    }
    set transmitters [get_cells -hier -filter {NAME =~ */u_tx}]
    if {[llength $transmitters]!=1 || [get_property NAME $transmitters] ne "u_core/u_tx"} {error "Unexpected UART TX branches: $transmitters"}
    puts $f "uart_tx=[get_property NAME $transmitters]"
    close $f
    place_design
    route_design
    report_utilization -hierarchical -file utilization_hierarchical.rpt
    report_utilization -file utilization.rpt
    report_timing_summary -report_unconstrained -file timing_summary.rpt
    report_drc -file drc.rpt
    report_cdc -details -file cdc.rpt
    report_io -file io.rpt
    report_exceptions -file exceptions.rpt
    set registers [all_registers -clock pl_clk_50m]
    set max_path [get_timing_paths -from $registers -to $registers -delay_type max -max_paths 1]
    set min_path [get_timing_paths -from $registers -to $registers -delay_type min -max_paths 1]
    if {[llength $max_path]!=1 || [llength $min_path]!=1} {error "Missing internal timing paths"}
    set setup [get_property SLACK $max_path];set hold [get_property SLACK $min_path]
    report_timing -of_objects $max_path -file internal_setup.rpt
    report_timing -of_objects $min_path -file internal_hold.rpt
    set sync_path [get_timing_paths -from [get_pins $prefix/rx_meta_reg/Q] -to [get_pins $prefix/rx_sync_reg/D] -max_paths 1]
    if {[llength $sync_path]!=1} {error "Synchronizer internal path missing"}
    report_timing -of_objects $sync_path -file rx_sync_timing.rpt
    if {$setup<0 || $hold<0} {error "Timing failed mode=$mode setup=$setup hold=$hold"}
    if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {error "DRC error or critical warning"}
    write_checkpoint -force routed_system.dcp
    set f [open $result w];puts $f "PASS stage6_implementation mode=$mode setup_slack=$setup hold_slack=$hold";close $f
    puts "PASS stage6 implementation $label setup=$setup hold=$hold"
    close_project
}
