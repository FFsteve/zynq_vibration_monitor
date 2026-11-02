`timescale 1ns/1ps
`default_nettype none

// 层级职责：第六阶段完整系统，把计算结果的观测与唯一外部UART回传整合到一起。
// u_processing提供raw/filtered/特征/报警；u_select按综合参数选数据；u_return排队；u_tx实际发送。
// RETURN_FILTERED是构建时参数，不是运行时自动识别；十字节包内没有模式字段，采集记录须写明模式。
// 计算层原有发送口不连接，外部pl_tx仅由本层u_tx驱动，避免双发送器竞争同一物理端口。
// 实际回传的accepted/dropped/completed来自本层u_return，而不是已断开旧发送支路的统计。
// tx_pause_i仅用于验证拥塞：同时阻止控制器握手和TX接单，不冻结正在发送的位，也不拦截done。
// 板级顶层把tx_pause_i接0；本层保留显式rst和丰富诊断口，便于独立仿真与ILA观察。

// 完整计算与唯一外部发送支路集成；暂停仅为内部拥塞验证接口。
module system_monitor_core #(
    parameter integer RETURN_FILTERED=0,
    parameter integer CLK_HZ=50000000,BAUD=115200,BYTE_TIMEOUT_CLKS=100000,
    parameter integer ACK_ONLY=0,QUEUE_DEPTH=4,GAP_TIMEOUT_CLKS=600000,WINDOW_LOG2=7,
    parameter integer RMS_ON=2000,RMS_OFF=1500,ASSERT_WINDOWS=2,RELEASE_WINDOWS=2,
    parameter COEFF_FILE="fir_lp_63_q16.mem"
)(
    input wire clk,rst,pl_rx,tx_pause_i,
    output wire pl_tx,
    output wire overflow_o,packet_done_o,selected_valid_o,
    output wire [7:0] selected_seq_o,
    output wire signed [15:0] selected_x_o,selected_y_o,selected_z_o,
    output wire [31:0] queued_count_o,
    output wire raw_valid_o,filtered_valid_o,history_full_o,quality_valid_o,
    output wire [7:0] raw_seq_o,filtered_seq_o,
    output wire signed [15:0] raw_x_o,raw_y_o,raw_z_o,
    output wire signed [17:0] filtered_x_o,filtered_y_o,filtered_z_o,
    output wire feature_valid_o,
    output wire [34:0] ms_x_o,ms_y_o,ms_z_o,
    output wire [17:0] rms_x_o,rms_y_o,rms_z_o,peak_x_o,peak_y_o,peak_z_o,
    output wire [7:0] seq_start_o,seq_end_o,
    output wire [31:0] window_id_o,
    output wire [2:0] alarm_axes_o,alarm_rise_o,alarm_fall_o,
    output wire alarm_any_o,alarm_valid_o,
    output wire window_overrun_o,window_discontinuity_o,
    output wire [31:0] window_accepted_count_o,window_dropped_count_o,aborted_windows_o,
    output wire [31:0] rx_frame_count_o,uart_error_count_o,checksum_error_count_o,timeout_count_o,
        seq_error_count_o,accepted_count_o,dropped_count_o,completed_count_o,
        filter_accepted_count_o,filter_dropped_count_o,filter_restart_count_o
);
    wire [7:0] tx_data;
    wire controller_valid,uart_ready,uart_done;
    wire permitted=!tx_pause_i;
    // 未连接的旧发送支路由综合移除，新支路计数单独对应实际外部回传。
    feature_monitor_core #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.BYTE_TIMEOUT_CLKS(BYTE_TIMEOUT_CLKS),
        .ACK_ONLY(ACK_ONLY),.QUEUE_DEPTH(QUEUE_DEPTH),.GAP_TIMEOUT_CLKS(GAP_TIMEOUT_CLKS),.WINDOW_LOG2(WINDOW_LOG2),
        .RMS_ON(RMS_ON),.RMS_OFF(RMS_OFF),.ASSERT_WINDOWS(ASSERT_WINDOWS),.RELEASE_WINDOWS(RELEASE_WINDOWS),.COEFF_FILE(COEFF_FILE)) u_processing(
        .clk(clk),.rst(rst),.pl_rx(pl_rx),.pl_tx(),.raw_valid_o(raw_valid_o),.filtered_valid_o(filtered_valid_o),.history_full_o(history_full_o),.quality_valid_o(quality_valid_o),.raw_seq_o(raw_seq_o),.filtered_seq_o(filtered_seq_o),.raw_x_o(raw_x_o),.raw_y_o(raw_y_o),.raw_z_o(raw_z_o),.filtered_x_o(filtered_x_o),.filtered_y_o(filtered_y_o),.filtered_z_o(filtered_z_o),.feature_valid_o(feature_valid_o),.ms_x_o(ms_x_o),.ms_y_o(ms_y_o),.ms_z_o(ms_z_o),.rms_x_o(rms_x_o),.rms_y_o(rms_y_o),.rms_z_o(rms_z_o),.peak_x_o(peak_x_o),.peak_y_o(peak_y_o),.peak_z_o(peak_z_o),.seq_start_o(seq_start_o),.seq_end_o(seq_end_o),.window_id_o(window_id_o),.alarm_axes_o(alarm_axes_o),.alarm_rise_o(alarm_rise_o),.alarm_fall_o(alarm_fall_o),.alarm_any_o(alarm_any_o),.alarm_valid_o(alarm_valid_o),.window_overrun_o(window_overrun_o),.window_discontinuity_o(window_discontinuity_o),.window_accepted_count_o(window_accepted_count_o),.window_dropped_count_o(window_dropped_count_o),.aborted_windows_o(aborted_windows_o),.rx_frame_count_o(rx_frame_count_o),.uart_error_count_o(uart_error_count_o),.checksum_error_count_o(checksum_error_count_o),.timeout_count_o(timeout_count_o),.seq_error_count_o(seq_error_count_o),.accepted_count_o(),.dropped_count_o(),.completed_count_o(),.filter_accepted_count_o(filter_accepted_count_o),.filter_dropped_count_o(filter_dropped_count_o),.filter_restart_count_o(filter_restart_count_o));
    // 先选样本和对应SEQ，再重新组包；这样原始/滤波模式都保持包的内部一致性。
    return_source_select #(.RETURN_FILTERED(RETURN_FILTERED)) u_select(
        .clk(clk),.rst(rst),.raw_valid_i(raw_valid_o),.filtered_valid_i(filtered_valid_o),
        .raw_seq_i(raw_seq_o),.filtered_seq_i(filtered_seq_o),.raw_x_i(raw_x_o),.raw_y_i(raw_y_o),.raw_z_i(raw_z_o),
        .filtered_x_i(filtered_x_o),.filtered_y_i(filtered_y_o),.filtered_z_i(filtered_z_o),
        .selected_valid_o(selected_valid_o),.seq_o(selected_seq_o),.x_o(selected_x_o),.y_o(selected_y_o),.z_o(selected_z_o));
    // 控制器看到的ready也必须被permitted门控，否则暂停时会误以为TX已接收而丢字节。
    return_controller #(.ACK_ONLY(ACK_ONLY),.QUEUE_DEPTH(QUEUE_DEPTH)) u_return(
        .clk(clk),.rst(rst),.frame_valid_i(selected_valid_o),.seq_i(selected_seq_o),.x_i(selected_x_o),.y_i(selected_y_o),.z_i(selected_z_o),
        .tx_data_o(tx_data),.tx_valid_o(controller_valid),.tx_ready_i(uart_ready && permitted),.tx_done_i(uart_done),
        .overflow_o(overflow_o),.packet_done_o(packet_done_o),.accepted_count_o(accepted_count_o),.dropped_count_o(dropped_count_o),
        .completed_count_o(completed_count_o),.queued_count_o(queued_count_o));
    // 暂停不冻结正在发送的字节，done始终返回，避免位宽损坏或重复握手。
    uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_tx(
        .clk(clk),.rst(rst),.data_i(tx_data),.valid_i(controller_valid && permitted),.ready_o(uart_ready),
        .tx_o(pl_tx),.busy_o(),.done_o(uart_done));
endmodule
`default_nettype wire
