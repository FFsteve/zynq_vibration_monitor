# 测试名称由专用进程环境变量传入，不更改用户的永久环境配置。
if {![info exists ::env(UART_STAGE2_TEST)]} {error "Missing UART_STAGE2_TEST"}
set test_name $::env(UART_STAGE2_TEST)
if {$test_name ni {packet_parser uart_tx uart_packet_link}} {error "Invalid test name"}
set top tb_${test_name}
log_wave -r /$top/*
run all
set done [get_value -radix unsigned /$top/test_done]
set errors [get_value -radix unsigned /$top/error_count]
if {$done != 1 || $errors != 0} {error "FAIL $test_name done=$done errors=$errors"}
puts "PASS XSim $test_name"
quit
