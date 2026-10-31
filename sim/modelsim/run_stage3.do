# 批处理参数：仓库根目录、测试名称；显式参数避免旧版 ModelSim 宏路径误判。
onerror {quit -force -code 1}
if {![info exists 1] || ![info exists 2]} {error "Usage: do run_stage3.do {root} {test}"}
set repo_root [file normalize [set 1]]
set test_name [set 2]
if {$test_name ni {power_on_reset return_controller monitor_core top}} {error "Invalid test name"}
if {![file isfile [file join $repo_root rtl packet_parser.v]]} {error "Invalid root"}
set out_dir [file join $repo_root build modelsim_stage3 $test_name]
file mkdir $out_dir
cd $out_dir
transcript file [file join $out_dir transcript.log]
if {![file exists [file join $out_dir work _info]]} {vlib work}
vmap work [file join $out_dir work]
vlog -work work [file join $repo_root rtl uart_rx.v] [file join $repo_root rtl uart_tx.v] [file join $repo_root rtl packet_parser.v] [file join $repo_root rtl power_on_reset.v] [file join $repo_root rtl return_controller.v] [file join $repo_root rtl monitor_core.v] [file join $repo_root rtl top.v] [file join $repo_root sim tb stage3_serial_case.v] [file join $repo_root sim tb tb_${test_name}.v]
set top tb_${test_name}
vsim -onfinish stop -voptargs=+acc work.$top
# 保存接口与内部信号，供定位首次失败；评分器本身不依赖这些波形记录。
log -r /$top/*
run -all
set done [examine -radix unsigned /$top/test_done]
set errors [examine -radix unsigned /$top/error_count]
if {$done != 1 || $errors != 0} {puts "FAIL $test_name done=$done errors=$errors";quit -force -code 1}
puts "PASS ModelSim $test_name"
quit -force -code 0
