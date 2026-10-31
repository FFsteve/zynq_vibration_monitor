# 参数为仓库根目录与测试名称，输出位于独立工作目录。
onerror {quit -force -code 1}
set repo_root [file normalize [set 1]]
set test_name [set 2]
if {$test_name ni {isqrt_u36 window_features threshold_alarm feature_monitor_core}} {error "Invalid test"}
set out_dir [file join $repo_root build modelsim_stage5 $test_name]
cd $out_dir
if {![file exists work/_info]} {vlib work}
vmap work [file join $out_dir work]
set sources [list +incdir+[file join $repo_root sim tb]]
foreach module {uart_rx uart_tx packet_parser power_on_reset return_controller monitor_core top dc_remove fir_lp_serial vibration_filter filter_monitor_core isqrt_u36 window_features threshold_alarm feature_monitor_core} {
    lappend sources [file join $repo_root rtl ${module}.v]
}
lappend sources [file join $repo_root sim tb tb_${test_name}.v]
eval vlog -work work $sources
set top tb_${test_name}
vsim -onfinish stop -voptargs=+acc work.$top
# 不递归记录整个历史数组，保留顶层接口及需要定位的内部寄存器。
log /$top/*
run -all
set done [examine -radix unsigned /$top/test_done]
set errors [examine -radix unsigned /$top/error_count]
if {$done!=1 || $errors!=0} {puts "FAIL $test_name done=$done errors=$errors";quit -force -code 1}
quit -force -code 0
