# 在独立目录逐个运行非法参数顶层，调用方检查实际拒绝标记。
onerror {quit -force -code 1}
set root [file normalize [set 1]]
set top [set 2]
if {![file exists work/_info]} {vlib work}
vmap work [file join [pwd] work]
foreach name {return_source_select} {vlog [file join $root rtl ${name}.v]}
vlog [file join $root sim tb stage6_negative_cases.v]
vsim -onfinish stop work.$top
run -all
quit -force -code 0
