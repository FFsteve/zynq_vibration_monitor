onerror {quit -force -code 1}
set root [file normalize [set 1]]
set name [set 2]
if {$name ni {missing_coeff invalid_gap}} {error "Invalid negative case"}
if {![file exists work/_info]} {vlib work}
vmap work [file join [pwd] work]
vlog [file join $root rtl dc_remove.v] [file join $root rtl fir_lp_serial.v] [file join $root rtl vibration_filter.v] [file join $root sim tb stage4_negative_cases.v]
vsim -onfinish stop work.tb_stage4_$name
run -all
if {[file exists unexpected_accept.txt]} {error "Negative guard failed"}
quit -force -code 0
