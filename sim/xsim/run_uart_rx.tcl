# 运行方式：xsim tb_uart_rx_sim -onfinish stop -tclbatch 本脚本路径。
log_wave -r /tb_uart_rx/main_case/dut/*
log_wave /tb_uart_rx/main_case/rx_i /tb_uart_rx/main_case/rst
run all
set done [get_value -radix unsigned /tb_uart_rx/test_done]
set errors [get_value -radix unsigned /tb_uart_rx/error_count]
if {$done != 1 || $errors != 0} {
    error "FAIL XSim: test_done=$done errors=$errors"
}
puts "PASS XSim UART RX regression"
quit
