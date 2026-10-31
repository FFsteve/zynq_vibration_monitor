if {![info exists ::env(UART_STAGE6_TEST)]} {error "Missing test"}
set test_name $::env(UART_STAGE6_TEST)
if {$test_name ni {return_source_select system_monitor_core system_top return_controller packet_parser}} {error "Invalid test"}
set top tb_${test_name}
log_wave /$top/*
if {$test_name eq "system_monitor_core"} {
 foreach branch {raw_case filtered_case} {
  foreach signal {rst rx tx pause raw_valid filtered_valid fv full quality av axes wid accepted dropped completed queued} {log_wave /$top/$branch/$signal}
 }
}
run all
set done [get_value -radix unsigned /$top/test_done]
set errors [get_value -radix unsigned /$top/error_count]
if {$done!=1 || $errors!=0} {error "FAIL $test_name done=$done errors=$errors"}
quit
