if {![info exists ::env(UART_STAGE5_TEST)]} {error "Missing test"}
set test_name $::env(UART_STAGE5_TEST)
if {$test_name ni {isqrt_u36 window_features threshold_alarm feature_monitor_core}} {error "Invalid test"}
set top tb_${test_name}
log_wave /$top/*
run all
set done [get_value -radix unsigned /$top/test_done]
set errors [get_value -radix unsigned /$top/error_count]
if {$done!=1 || $errors!=0} {error "FAIL $test_name done=$done errors=$errors"}
quit
