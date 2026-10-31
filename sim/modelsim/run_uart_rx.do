# 批处理入口：vsim -c -do "do {本脚本路径} {仓库根目录}"
# 自动生成的仿真库、日志和结果统一写入 build/。
onerror {quit -force -code 1}
# ModelSim 的 .do 宏不能可靠地通过 [info script] 获取自身路径。
# 由 PowerShell 入口将仓库根目录作为宏的第一个参数传入。
if {![info exists 1]} {
    error "Usage: do run_uart_rx.do {absolute-repository-root}"
}
set repo_root [file normalize [set 1]]
if {![file isfile [file join $repo_root rtl uart_rx.v]]} {
    error "Invalid repository root: $repo_root"
}
set out_dir [file join $repo_root build modelsim_uart_rx]
file mkdir $out_dir
cd $out_dir
transcript file [file join $out_dir transcript.log]
if {![file exists [file join $out_dir work _info]]} {
    vlib work
}
vmap work [file join $out_dir work]
vlog -work work [file join $repo_root rtl uart_rx.v] [file join $repo_root sim tb tb_uart_rx.v]
vsim -onfinish stop -voptargs=+acc work.tb_uart_rx
log -r /tb_uart_rx/main_case/dut/*
log /tb_uart_rx/main_case/rx_i /tb_uart_rx/main_case/rst
run -all
set done [examine -radix unsigned /tb_uart_rx/test_done]
set errors [examine -radix unsigned /tb_uart_rx/error_count]
if {$done != 1 || $errors != 0} {
    puts "FAIL ModelSim: test_done=$done errors=$errors"
    quit -force -code 1
}
puts "PASS ModelSim UART RX regression"
quit -force -code 0
