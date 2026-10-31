# 在当前已打开的Vivado工程中使用；配置顶层、CDC适用阶段和完整系统的系数资源。
# 可预先设置vibration_top为system_top或top；未设置时保留当前设计顶层。
namespace eval ::vibration_cdc {
    proc register_coefficients {root} {
        set name fir_lp_63_q16.mem
        set path [file normalize [file join $root data reference stage4 $name]]
        if {![file isfile $path] || ![file readable $path]} {error "Missing or unreadable FIR coefficients: $path"}
        set stream [open $path r]
        set words [regexp -all -inline {\S+} [read $stream]]
        close $stream
        if {[llength $words]!=63} {error "Expected 63 FIR coefficients: $path"}
        foreach word $words {
            if {![regexp {^[0-3][0-9a-fA-F]{4}$} $word]} {error "Invalid 18-bit FIR coefficient: $word"}
        }
        # 按文件名检查冲突，避免另一个目录中的同名旧系数被工具误用。
        set matches [list]
        foreach item [get_files -quiet -of_objects [get_filesets sources_1]] {
            if {[file tail [get_property NAME $item]] eq $name} {
                if {[file normalize [get_property NAME $item]] ne $path} {error "Conflicting FIR coefficient file: $item"}
                lappend matches $item
            }
        }
        if {[llength $matches]>1} {error "Duplicate FIR coefficient files: $matches"}
        if {[llength $matches]==0} {add_files -fileset sources_1 -norecurse $path}
        set item [get_files $path]
        set_property IS_ENABLED true $item
        set_property USED_IN {synthesis implementation simulation} $item
        puts "PASS project_memory file=$path words=63 type=[get_property FILE_TYPE $item]"
    }

    proc find_constraint {root name} {
        set matches [list]
        foreach item [get_files -quiet -of_objects [get_filesets constrs_1]] {
            if {[file tail [get_property NAME $item]] eq $name} {lappend matches $item}
        }
        if {[llength $matches]==0} {
            set path [file join $root constr $name]
            if {![file exists $path]} {error "Missing constraint file: $path"}
            add_files -fileset constrs_1 -norecurse $path
            foreach item [get_files -quiet -of_objects [get_filesets constrs_1]] {
                if {[file tail [get_property NAME $item]] eq $name} {lappend matches $item}
            }
        }
        if {[llength $matches]!=1} {error "Expected one constraint file named $name, got $matches"}
        return [lindex $matches 0]
    }

    proc configure {root target} {
        if {[llength [get_projects -quiet]]!=1} {error "Open the intended Vivado project first"}
        if {$target ni {top system_top}} {error "Supported design tops: top, system_top"}
        set sources [get_filesets sources_1]
        set selected_name [expr {$target eq "system_top" ? "system_uart_rx_cdc.xdc" : "uart_rx_cdc.xdc"}]
        # 先确定文件对象，文件缺失时不得只完成一半配置。
        set legacy [find_constraint $root uart_rx_cdc.xdc]
        set system [find_constraint $root system_uart_rx_cdc.xdc]
        if {$target eq "system_top"} {register_coefficients $root}
        foreach item [list $legacy $system] {
            set_property USED_IN_SYNTHESIS false $item
            set enabled [expr {[file tail [get_property NAME $item]] eq $selected_name}]
            set_property USED_IN_IMPLEMENTATION $enabled $item
            set_property IS_ENABLED $enabled $item
        }
        set_property TOP $target $sources
        update_compile_order -fileset sources_1
        puts "PASS project_cdc top=$target selected=$selected_name synthesis=false implementation=true"
        puts "Close and reopen Elaborated Design; these settings do not reload an already-open netlist."
        return $selected_name
    }
}
set vibration_cdc_root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists vibration_top]} {set vibration_top [get_property TOP [get_filesets sources_1]]}
::vibration_cdc::configure $vibration_cdc_root $vibration_top
