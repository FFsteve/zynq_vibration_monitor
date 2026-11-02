`timescale 1ns/1ps
`default_nettype none

// 入口用途：完整滤波/统计/报警的历史板级顶层，默认RETURN_FILTERED=0，无beep输出。
//
// 主链由power_on_reset和system_monitor_core组成；所有计算、发送与调试寄存器都使用同一clk。
// 保留21组共427位debug快照，并使用MARK_DEBUG与DONT_TOUCH保留真实寄存器负载。
// 为何要有负载：只声明未被使用的统计信号仍可能被综合裁掉，导致软件仿真有算法、实际bit中没有。
// 每拍复制核心状态到debug寄存器，快照整体比核心晚一拍，但不反馈、不改变滤波或报警计算。
// feature_valid是新窗口的一拍事件；RMS/峰值在窗口间保持，不能把其保持时间理解成新数据频率。
// 仅加MARK_DEBUG不会自动插入ILA，实际调试核由构建约束/脚本创建；bit与ltx必须来自匹配构建。

// 独立板级入口；不改旧top或本地工程，调试标记不自动创建ILA。
module system_top #(
    parameter integer RETURN_FILTERED=0,CLK_HZ=50000000,BAUD=115200,
    parameter integer RESET_HOLD_CLKS=1024,BYTE_TIMEOUT_CLKS=100000,ACK_ONLY=0,QUEUE_DEPTH=4,
    parameter integer GAP_TIMEOUT_CLKS=600000,WINDOW_LOG2=7,
    parameter COEFF_FILE="fir_lp_63_q16.mem"
)(input wire clk,pl_rx,output wire pl_tx);
    wire rst;
    power_on_reset #(.HOLD_CLKS(RESET_HOLD_CLKS)) u_reset(.clk(clk),.restart_i(1'b0),.rst_o(rst));
    // 以下wire是核心功能结果，debug_*是独立观测寄存器；分开命名，避免调试信号被误接回主链。
    wire  feature_valid_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg  debug_feature_valid_o;
    wire [34:0] ms_x_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [34:0] debug_ms_x_o;
    wire [34:0] ms_y_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [34:0] debug_ms_y_o;
    wire [34:0] ms_z_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [34:0] debug_ms_z_o;
    wire [17:0] rms_x_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [17:0] debug_rms_x_o;
    wire [17:0] rms_y_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [17:0] debug_rms_y_o;
    wire [17:0] rms_z_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [17:0] debug_rms_z_o;
    wire [17:0] peak_x_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [17:0] debug_peak_x_o;
    wire [17:0] peak_y_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [17:0] debug_peak_y_o;
    wire [17:0] peak_z_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [17:0] debug_peak_z_o;
    wire [7:0] seq_start_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [7:0] debug_seq_start_o;
    wire [7:0] seq_end_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [7:0] debug_seq_end_o;
    wire [31:0] window_id_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [31:0] debug_window_id_o;
    wire [2:0] alarm_axes_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [2:0] debug_alarm_axes_o;
    wire  alarm_valid_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg  debug_alarm_valid_o;
    wire  quality_valid_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg  debug_quality_valid_o;
    wire [31:0] rx_frame_count_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [31:0] debug_rx_frame_count_o;
    wire [31:0] dropped_count_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [31:0] debug_dropped_count_o;
    wire [31:0] completed_count_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [31:0] debug_completed_count_o;
    wire [31:0] filter_restart_count_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [31:0] debug_filter_restart_count_o;
    wire [31:0] aborted_windows_o;
    (* MARK_DEBUG="TRUE", DONT_TOUCH="TRUE" *) reg [31:0] debug_aborted_windows_o;
    // 板级不暴露拥塞注入，把tx_pause_i固定为0；其余未使用诊断口可留空，不额外增加外部引脚。
    system_monitor_core #(.RETURN_FILTERED(RETURN_FILTERED),.CLK_HZ(CLK_HZ),.BAUD(BAUD),
        .BYTE_TIMEOUT_CLKS(BYTE_TIMEOUT_CLKS),.ACK_ONLY(ACK_ONLY),.QUEUE_DEPTH(QUEUE_DEPTH),
        .GAP_TIMEOUT_CLKS(GAP_TIMEOUT_CLKS),.WINDOW_LOG2(WINDOW_LOG2),.COEFF_FILE(COEFF_FILE)) u_core(
        .clk(clk),.rst(rst),.pl_rx(pl_rx),.tx_pause_i(1'b0),.pl_tx(pl_tx),.overflow_o(),.packet_done_o(),.selected_valid_o(),.selected_seq_o(),.selected_x_o(),.selected_y_o(),.selected_z_o(),.queued_count_o(),.raw_valid_o(),.filtered_valid_o(),.history_full_o(),.quality_valid_o(quality_valid_o),.raw_seq_o(),.filtered_seq_o(),.raw_x_o(),.raw_y_o(),.raw_z_o(),.filtered_x_o(),.filtered_y_o(),.filtered_z_o(),.feature_valid_o(feature_valid_o),.ms_x_o(ms_x_o),.ms_y_o(ms_y_o),.ms_z_o(ms_z_o),.rms_x_o(rms_x_o),.rms_y_o(rms_y_o),.rms_z_o(rms_z_o),.peak_x_o(peak_x_o),.peak_y_o(peak_y_o),.peak_z_o(peak_z_o),.seq_start_o(seq_start_o),.seq_end_o(seq_end_o),.window_id_o(window_id_o),.alarm_axes_o(alarm_axes_o),.alarm_rise_o(),.alarm_fall_o(),.alarm_any_o(),.alarm_valid_o(alarm_valid_o),.window_overrun_o(),.window_discontinuity_o(),.window_accepted_count_o(),.window_dropped_count_o(),.aborted_windows_o(aborted_windows_o),.rx_frame_count_o(rx_frame_count_o),.uart_error_count_o(),.checksum_error_count_o(),.timeout_count_o(),.seq_error_count_o(),.accepted_count_o(),.dropped_count_o(dropped_count_o),.completed_count_o(completed_count_o),.filter_accepted_count_o(),.filter_dropped_count_o(),.filter_restart_count_o(filter_restart_count_o));
    // 具有真实寄存器负载的调试快照；只供最终观测，不参与功能反馈。
    always @(posedge clk) begin
        if(rst)begin
            debug_feature_valid_o<=0;
            debug_ms_x_o<=0;
            debug_ms_y_o<=0;
            debug_ms_z_o<=0;
            debug_rms_x_o<=0;
            debug_rms_y_o<=0;
            debug_rms_z_o<=0;
            debug_peak_x_o<=0;
            debug_peak_y_o<=0;
            debug_peak_z_o<=0;
            debug_seq_start_o<=0;
            debug_seq_end_o<=0;
            debug_window_id_o<=0;
            debug_alarm_axes_o<=0;
            debug_alarm_valid_o<=0;
            debug_quality_valid_o<=0;
            debug_rx_frame_count_o<=0;
            debug_dropped_count_o<=0;
            debug_completed_count_o<=0;
            debug_filter_restart_count_o<=0;
            debug_aborted_windows_o<=0;
        // 每拍复制而非仅在feature_valid时复制，才能同时观察有效位变化、断流失效与累计计数。
        end else begin
            debug_feature_valid_o<=feature_valid_o;
            debug_ms_x_o<=ms_x_o;
            debug_ms_y_o<=ms_y_o;
            debug_ms_z_o<=ms_z_o;
            debug_rms_x_o<=rms_x_o;
            debug_rms_y_o<=rms_y_o;
            debug_rms_z_o<=rms_z_o;
            debug_peak_x_o<=peak_x_o;
            debug_peak_y_o<=peak_y_o;
            debug_peak_z_o<=peak_z_o;
            debug_seq_start_o<=seq_start_o;
            debug_seq_end_o<=seq_end_o;
            debug_window_id_o<=window_id_o;
            debug_alarm_axes_o<=alarm_axes_o;
            debug_alarm_valid_o<=alarm_valid_o;
            debug_quality_valid_o<=quality_valid_o;
            debug_rx_frame_count_o<=rx_frame_count_o;
            debug_dropped_count_o<=dropped_count_o;
            debug_completed_count_o<=completed_count_o;
            debug_filter_restart_count_o<=filter_restart_count_o;
            debug_aborted_windows_o<=aborted_windows_o;
        end
    end
endmodule
`default_nettype wire
