# 新建隔离工程重现警告并验证两种顶层；不打开用户工程、不改其缓存或下载设置。
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build project_cdc_check]
file mkdir $out
cd $out
set result [open result.txt w];puts $result "NOT_RUN";close $result
create_project -in_memory -part xc7z010clg400-1
foreach module {uart_rx uart_tx packet_parser power_on_reset return_controller monitor_core top dc_remove fir_lp_serial vibration_filter filter_monitor_core isqrt_u36 window_features threshold_alarm feature_monitor_core return_source_select system_monitor_core system_top} {
    add_files -norecurse [file join $root rtl ${module}.v]
}
file copy -force [file join $root data reference stage4 fir_lp_63_q16.mem] [file join $out fir_lp_63_q16.mem]
foreach name {top.xdc uart_rx_cdc.xdc system_uart_rx_cdc.xdc} {add_files -fileset constrs_1 -norecurse [file join $root constr $name]}
set_property TOP top [get_filesets sources_1]
set_property USED_IN_SYNTHESIS false [get_files */uart_rx_cdc.xdc]
set_property USED_IN_SYNTHESIS true [get_files */system_uart_rx_cdc.xdc]
puts "CHECK_BEGIN original_mismatch"
set original_failed [catch {synth_design -rtl -name original_rtl -top top -part xc7z010clg400-1} original_error]
puts "CHECK_ORIGINAL command_failed=$original_failed message=$original_error"
if {[llength [get_designs -quiet]]} {
    set old_pin [get_pins -quiet u_core/u_processing/filtering/communication/u_rx/rx_meta_reg/D]
    if {[llength $old_pin]!=0} {error "Expected mismatch in legacy top"}
    close_design
}
puts "CHECK_END original_mismatch"
set checks [list]
foreach target {top system_top} {
    set vibration_top $target
    source [file join $root scripts configure_project_cdc.tcl]
    foreach name {uart_rx_cdc.xdc system_uart_rx_cdc.xdc} {
        set item [get_files */$name]
        if {[get_property USED_IN_SYNTHESIS $item]} {error "CDC still active for synthesis: $name"}
        set expected [expr {($target eq "top" && $name eq "uart_rx_cdc.xdc") || ($target eq "system_top" && $name eq "system_uart_rx_cdc.xdc")}]
        if {[get_property IS_ENABLED $item]!=$expected || [get_property USED_IN_IMPLEMENTATION $item]!=$expected} {error "Wrong active CDC for $target"}
    }
    puts "CHECK_BEGIN fixed_elaboration_$target"
    synth_design -rtl -name rtl_$target -top $target -part xc7z010clg400-1
    close_design
    puts "CHECK_END fixed_elaboration_$target"
    puts "CHECK_BEGIN synthesized_$target"
    synth_design -top $target -part xc7z010clg400-1
    set prefix [expr {$target eq "top" ? "u_core/u_rx" : "u_core/u_processing/filtering/communication/u_rx"}]
    set first [get_pins -quiet $prefix/rx_meta_reg/D]
    if {[llength $first]!=1} {error "Missing first-stage D after synthesis: $prefix"}
    set file_name [expr {$target eq "top" ? "uart_rx_cdc.xdc" : "system_uart_rx_cdc.xdc"}]
    read_xdc [file join $root constr $file_name]
    set sync_path [get_timing_paths -from [get_pins $prefix/rx_meta_reg/Q] -to [get_pins $prefix/rx_sync_reg/D] -max_paths 1]
    if {[llength $sync_path]!=1} {error "Second synchronizer stage lost timing coverage"}
    report_timing -of_objects $sync_path -file ${target}_sync_timing.rpt
    report_exceptions -file ${target}_exceptions.rpt
    lappend checks "${target}:elaboration_ok:first_stage_D=1:second_stage_timed=1"
    close_design
    puts "CHECK_END synthesized_$target"
}
set result [open result.txt w]
puts $result "PASS project_cdc [join $checks { }]"
close $result
close_project
