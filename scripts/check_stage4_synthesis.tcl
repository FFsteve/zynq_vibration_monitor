# 独立OOC实现检查；不打开本地板级工程或连接硬件。
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build stage4_synthesis]
file mkdir $out
cd $out
set result_path [file join $out synthesis_result.txt]
set f [open $result_path w];puts $f "NOT_RUN";close $f
create_project -in_memory -part xc7z010clg400-1
foreach module {dc_remove fir_lp_serial vibration_filter} {
    read_verilog [file join $root rtl ${module}.v]
}
synth_design -mode out_of_context -top vibration_filter -part xc7z010clg400-1
create_clock -period 20.000 -name filter_clk [get_ports clk]
# 没有父级数据路径，端口延迟留待最终集成；内部寄存器路径严格按20ns验收。
# 不用虚构的0ns接口保持预算代表板级约束，也不添加false_path隐藏内部路径。
opt_design
place_design
route_design
report_utilization -file utilization.rpt
report_timing_summary -report_unconstrained -file timing_summary.rpt
report_drc -file drc.rpt
set registers [all_registers -clock filter_clk]
set max_path [get_timing_paths -from $registers -to $registers -delay_type max -max_paths 1]
set min_path [get_timing_paths -from $registers -to $registers -delay_type min -max_paths 1]
report_timing -from $registers -to $registers -delay_type max -max_paths 10 -file internal_setup.rpt
report_timing -from $registers -to $registers -delay_type min -max_paths 10 -file internal_hold.rpt
if {[llength $max_path]!=1 || [llength $min_path]!=1} {error "Missing timing paths"}
set setup [get_property SLACK $max_path]
set hold [get_property SLACK $min_path]
if {$setup<0 || $hold<0} {error "OOC timing failed setup=$setup hold=$hold"}
set violations [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]
if {[llength $violations]} {error "OOC DRC errors or critical warnings: $violations"}
write_checkpoint -force routed_filter.dcp
set f [open $result_path w]
puts $f "PASS stage4_ooc setup_slack=$setup hold_slack=$hold"
close $f
puts "PASS stage4 OOC setup=$setup hold=$hold"
close_project
