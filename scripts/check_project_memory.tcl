# 使用独立的持久工程验证GUI工程模式的系数查找，不复制系数到工作目录。
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build project_memory_check]
file mkdir $out
cd $out
set result [open result.txt w]; puts $result NOT_RUN; close $result
if {[file exists fir_lp_63_q16.mem]} {error "Test requires no coefficient copy in the working directory"}
create_project -force memory_check [file join $out project] -part xc7z010clg400-1
foreach module {uart_rx uart_tx packet_parser power_on_reset return_controller monitor_core top dc_remove fir_lp_serial vibration_filter filter_monitor_core isqrt_u36 window_features threshold_alarm feature_monitor_core return_source_select system_monitor_core system_top} {
    add_files -norecurse [file join $root rtl ${module}.v]
}
foreach name {top.xdc uart_rx_cdc.xdc system_uart_rx_cdc.xdc} {add_files -fileset constrs_1 -norecurse [file join $root constr $name]}
set_property TOP system_top [get_filesets sources_1]
set_property USED_IN_SYNTHESIS false [get_files */uart_rx_cdc.xdc]
set_property USED_IN_SYNTHESIS false [get_files */system_uart_rx_cdc.xdc]
# 先保留未登记文件的对照，确认本次测试确实覆盖缺资源场景。
puts "CHECK_BEGIN missing_memory"
synth_design -rtl -name missing_memory -top system_top -part xc7z010clg400-1
close_design
puts "CHECK_END missing_memory"
set vibration_top system_top
source [file join $root scripts configure_project_cdc.tcl]
# 重复执行不应产生重复源文件。
source [file join $root scripts configure_project_cdc.tcl]
if {[llength [get_files */fir_lp_63_q16.mem]]!=1} {error "Expected exactly one registered coefficient file"}
puts "CHECK_BEGIN fixed_elaboration"
synth_design -rtl -name fixed_memory -top system_top -part xc7z010clg400-1
close_design
puts "CHECK_END fixed_elaboration"
puts "CHECK_BEGIN fixed_synthesis"
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%" || [get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {error "Project synthesis did not complete successfully"}
open_run synth_1
set first [get_pins -quiet u_core/u_processing/filtering/communication/u_rx/rx_meta_reg/D]
if {[llength $first]!=1} {error "CDC endpoint missing after project synthesis"}
report_utilization -file [file join $out utilization.rpt]
set run_dir [get_property DIRECTORY [get_runs synth_1]]
set stream [open [file join $run_dir runme.log] r]
set synthesis_log [read $stream]; close $stream
if {[regexp {Synth 8-4445|could not open.*readmem|ERROR:|CRITICAL WARNING:} $synthesis_log]} {error "Project synthesis has a memory or critical diagnostic; inspect runme.log"}
set result [open result.txt w]
puts $result "PASS project_memory registered_files=1 fixed_elaboration=done project_synthesis=done missing_memory_warnings=0"
puts $result "synthesis_log=$run_dir/runme.log"
close $result
puts "CHECK_END fixed_synthesis"
close_project
