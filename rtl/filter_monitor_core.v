`timescale 1ns/1ps
`default_nettype none

// 层级职责：第四阶段在已验证通信旁增加计算支路，保留原始UART回传作对照。
// monitor_core提交一包后，vibration_filter消费同一份raw数值和SEQ，不从串行线重复解码。
// 滤波signed18结果只导出内部端口，本层的pl_tx仍是原始signed16包，避免混淆测量模式。
// raw_valid_o与filtered_valid_o间有确定计算延迟；用各自SEQ对应样本，不能只按同拍数值比较。
// 通信队列的dropped和滤波忙时的filter_dropped含义不同，分开输出以免把瓶颈归错模块。
// 参数逐层传递，系数文件、字节超时、断流超时必须与测试/构建时的配置一致。

// 在原始通信旁增加计算支路；滤波结果只作为内部接口导出。
module filter_monitor_core #(
    parameter integer CLK_HZ=50000000,BAUD=115200,BYTE_TIMEOUT_CLKS=100000,
    parameter integer ACK_ONLY=0,QUEUE_DEPTH=4,GAP_TIMEOUT_CLKS=600000,
    parameter COEFF_FILE="fir_lp_63_q16.mem"
) (
    input wire clk,rst,pl_rx,
    output wire pl_tx,
    output wire [7:0] raw_seq_o,filtered_seq_o,
    output wire signed [15:0] raw_x_o,raw_y_o,raw_z_o,
    output wire raw_valid_o,filtered_valid_o,
    output wire signed [17:0] filtered_x_o,filtered_y_o,filtered_z_o,
    output wire history_full_o,saturated_o,filter_ready_o,overrun_o,stream_restart_o,
    output wire [31:0] rx_frame_count_o,uart_error_count_o,checksum_error_count_o,
        timeout_count_o,seq_error_count_o,accepted_count_o,dropped_count_o,completed_count_o,
        filter_accepted_count_o,filter_dropped_count_o,filter_restart_count_o
);
    wire busy_unused;
    // 旧通信主链保持独立，供分阶段定位；上层完整系统可舍弃该旧发送端并建立唯一实际回传。
    monitor_core #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.BYTE_TIMEOUT_CLKS(BYTE_TIMEOUT_CLKS),
        .ACK_ONLY(ACK_ONLY),.QUEUE_DEPTH(QUEUE_DEPTH)) communication (
        .clk(clk),.rst(rst),.pl_rx(pl_rx),.pl_tx(pl_tx),.seq_o(raw_seq_o),
        .x_o(raw_x_o),.y_o(raw_y_o),.z_o(raw_z_o),.frame_valid_o(raw_valid_o),
        .rx_frame_count_o(rx_frame_count_o),.uart_error_count_o(uart_error_count_o),
        .checksum_error_count_o(checksum_error_count_o),.timeout_count_o(timeout_count_o),
        .seq_error_count_o(seq_error_count_o),.accepted_count_o(accepted_count_o),
        .dropped_count_o(dropped_count_o),.completed_count_o(completed_count_o));
    // 三轴包原子提交后才触发运算；history_full和restart由该模块维护，供后续窗口质量门控。
    vibration_filter #(.GAP_TIMEOUT_CLKS(GAP_TIMEOUT_CLKS),.COEFF_FILE(COEFF_FILE)) processing (
        .clk(clk),.rst(rst),.frame_valid_i(raw_valid_o),.seq_i(raw_seq_o),
        .x_i(raw_x_o),.y_i(raw_y_o),.z_i(raw_z_o),.ready_o(filter_ready_o),.busy_o(busy_unused),
        .filtered_valid_o(filtered_valid_o),.seq_o(filtered_seq_o),.x_o(filtered_x_o),
        .y_o(filtered_y_o),.z_o(filtered_z_o),.history_full_o(history_full_o),
        .saturated_o(saturated_o),.overrun_o(overrun_o),.stream_restart_o(stream_restart_o),
        .accepted_count_o(filter_accepted_count_o),.dropped_count_o(filter_dropped_count_o),
        .restart_count_o(filter_restart_count_o));
endmodule
`default_nettype wire
