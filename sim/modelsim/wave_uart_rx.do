# 在 ModelSim 图形界面加载 work.tb_uart_rx 后执行本脚本，添加观察波形。
add wave /tb_uart_rx/main_case/clk
add wave /tb_uart_rx/main_case/rst
add wave /tb_uart_rx/main_case/rx_i
add wave /tb_uart_rx/main_case/dut/rx_meta
add wave /tb_uart_rx/main_case/dut/rx_sync
add wave -radix unsigned /tb_uart_rx/main_case/dut/state
add wave -radix unsigned /tb_uart_rx/main_case/dut/baud_cnt
add wave -radix unsigned /tb_uart_rx/main_case/dut/bit_idx
add wave -radix hexadecimal /tb_uart_rx/main_case/dut/shift_reg
add wave -radix hexadecimal /tb_uart_rx/main_case/data_o
add wave /tb_uart_rx/main_case/valid_o
add wave /tb_uart_rx/main_case/framing_error_o
add wave /tb_uart_rx/main_case/busy_o
add wave -radix unsigned /tb_uart_rx/main_case/error_count
configure wave -timelineunits us
