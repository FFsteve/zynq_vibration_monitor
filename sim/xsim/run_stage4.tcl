if {![info exists ::env(UART_STAGE4_TEST)]} {error "Missing test"}
set test_name $::env(UART_STAGE4_TEST)
if {$test_name ni {dc_remove fir_lp_serial vibration_filter filter_monitor_core}} {error "Invalid test"}
set top tb_${test_name}
log_wave /$top/*
run all
set done [get_value -radix unsigned /$top/test_done]
set errors [get_value -radix unsigned /$top/error_count]
if {$done!=1 || $errors!=0} {error "FAIL $test_name done=$done errors=$errors"}
quit
