`timescale 1ns/1ps
`default_nettype none

// 层级职责：第五阶段把滤波、窗口和报警串起来，保证对外特征与更新后的报警对应同一窗口。
// window_clear覆盖历史未满、饱和、滤波过载与重启；alarm_clear再加入窗口过载/SEQ断续。
// 质量无效时不能把残留数值当成可信静止，也不能保留上一个数据段的报警。
// 质量有效只表示当前计算链条件满足；alarm_valid还要求已发布过完整窗口，两者分开表达。
// window_features的fv先驱动报警寄存器，本层在同一沿复制特征，故外部feature_valid与新报警对齐。
// 无新特征时MS/RMS/峰值保持旧值，读取时应看feature_valid事件以及quality/alarm有效状态。
// 本层仍沿用历史原始回传；完整系统的raw/filtered回传选择位于system_monitor_core。

// 保留原始回传，在内部增加可信窗口和报警；新窗口与更新后的报警同拍发布。
module feature_monitor_core #(
    parameter integer CLK_HZ=50000000,BAUD=115200,BYTE_TIMEOUT_CLKS=100000,
    parameter integer ACK_ONLY=0,QUEUE_DEPTH=4,GAP_TIMEOUT_CLKS=600000,WINDOW_LOG2=7,
    parameter integer RMS_ON=2000,RMS_OFF=1500,ASSERT_WINDOWS=2,RELEASE_WINDOWS=2,
    parameter COEFF_FILE="fir_lp_63_q16.mem"
)(
    input wire clk,rst,pl_rx,
    output wire pl_tx,
    output wire raw_valid_o,filtered_valid_o,history_full_o,quality_valid_o,
    output wire [7:0] raw_seq_o,filtered_seq_o,
    output wire signed [15:0] raw_x_o,raw_y_o,raw_z_o,
    output wire signed [17:0] filtered_x_o,filtered_y_o,filtered_z_o,
    output reg feature_valid_o,
    output reg [34:0] ms_x_o,ms_y_o,ms_z_o,
    output reg [17:0] rms_x_o,rms_y_o,rms_z_o,peak_x_o,peak_y_o,peak_z_o,
    output reg [7:0] seq_start_o,seq_end_o,
    output reg [31:0] window_id_o,
    output wire [2:0] alarm_axes_o,alarm_rise_o,alarm_fall_o,
    output wire alarm_any_o,alarm_valid_o,
    output wire window_overrun_o,window_discontinuity_o,
    output wire [31:0] window_accepted_count_o,window_dropped_count_o,aborted_windows_o,
    output wire [31:0] rx_frame_count_o,uart_error_count_o,checksum_error_count_o,timeout_count_o,
        seq_error_count_o,accepted_count_o,dropped_count_o,completed_count_o,
        filter_accepted_count_o,filter_dropped_count_o,filter_restart_count_o
);
    wire saturated,filter_overrun,restart;
    wire [34:0] mx,my,mz;
    wire [17:0] rx,ry,rz,px,py,pz;
    wire [7:0] ss,se;
    wire [31:0] wid;
    wire fv;
    // 任何失效都取消当前窗口并撤销可信标志，防止把预热样本、饱和结果或跨缺口数据用于报警。
    wire window_clear=!history_full_o || saturated || filter_overrun || restart;
    wire alarm_clear=window_clear || window_overrun_o || window_discontinuity_o;
    assign quality_valid_o=!rst && !alarm_clear;
    filter_monitor_core #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.BYTE_TIMEOUT_CLKS(BYTE_TIMEOUT_CLKS),.ACK_ONLY(ACK_ONLY),
        .QUEUE_DEPTH(QUEUE_DEPTH),.GAP_TIMEOUT_CLKS(GAP_TIMEOUT_CLKS),.COEFF_FILE(COEFF_FILE)) filtering(
        .clk(clk),.rst(rst),.pl_rx(pl_rx),.pl_tx(pl_tx),.raw_seq_o(raw_seq_o),.raw_x_o(raw_x_o),.raw_y_o(raw_y_o),.raw_z_o(raw_z_o),
        .raw_valid_o(raw_valid_o),.filtered_seq_o(filtered_seq_o),.filtered_x_o(filtered_x_o),.filtered_y_o(filtered_y_o),.filtered_z_o(filtered_z_o),
        .filtered_valid_o(filtered_valid_o),.history_full_o(history_full_o),.saturated_o(saturated),.overrun_o(filter_overrun),.stream_restart_o(restart),
        .rx_frame_count_o(rx_frame_count_o),.uart_error_count_o(uart_error_count_o),.checksum_error_count_o(checksum_error_count_o),
        .timeout_count_o(timeout_count_o),.seq_error_count_o(seq_error_count_o),.accepted_count_o(accepted_count_o),.dropped_count_o(dropped_count_o),
        .completed_count_o(completed_count_o),.filter_accepted_count_o(filter_accepted_count_o),.filter_dropped_count_o(filter_dropped_count_o),.filter_restart_count_o(filter_restart_count_o),
        .filter_ready_o());
    window_features #(.WINDOW_LOG2(WINDOW_LOG2)) features(.clk(clk),.rst(rst),.clear_i(window_clear),
        .sample_valid_i(filtered_valid_o),.seq_i(filtered_seq_o),.x_i(filtered_x_o),.y_i(filtered_y_o),.z_i(filtered_z_o),
        .feature_valid_o(fv),.ms_x_o(mx),.ms_y_o(my),.ms_z_o(mz),.rms_x_o(rx),.rms_y_o(ry),.rms_z_o(rz),
        .peak_x_o(px),.peak_y_o(py),.peak_z_o(pz),.seq_start_o(ss),.seq_end_o(se),.window_id_o(wid),
        .overrun_o(window_overrun_o),.discontinuity_o(window_discontinuity_o),.accepted_count_o(window_accepted_count_o),
        .dropped_count_o(window_dropped_count_o),.aborted_windows_o(aborted_windows_o),
        .ready_o());
    // 报警使用窗口原始fv和MS；外部复制寄存器晚一拍可见，正好与报警本拍更新对齐。
    threshold_alarm #(.RMS_ON(RMS_ON),.RMS_OFF(RMS_OFF),.ASSERT_WINDOWS(ASSERT_WINDOWS),.RELEASE_WINDOWS(RELEASE_WINDOWS)) alarm(
        .clk(clk),.rst(rst),.clear_i(alarm_clear),.feature_valid_i(fv),.ms_x_i(mx),.ms_y_i(my),.ms_z_i(mz),
        .alarm_axes_o(alarm_axes_o),.alarm_any_o(alarm_any_o),.alarm_valid_o(alarm_valid_o),.rise_o(alarm_rise_o),.fall_o(alarm_fall_o));
    always @(posedge clk) begin
        if(rst) begin
            feature_valid_o<=0;ms_x_o<=0;ms_y_o<=0;ms_z_o<=0;rms_x_o<=0;rms_y_o<=0;rms_z_o<=0;
            peak_x_o<=0;peak_y_o<=0;peak_z_o<=0;seq_start_o<=0;seq_end_o<=0;window_id_o<=0;
        end else begin
            // 在发布边界再检查alarm_clear，故障与窗口完成同拍时优先丢弃，不能泄漏一个看似有效的旧结果。
            feature_valid_o<=fv && !alarm_clear;
            if(fv && !alarm_clear) begin
                ms_x_o<=mx;ms_y_o<=my;ms_z_o<=mz;rms_x_o<=rx;rms_y_o<=ry;rms_z_o<=rz;
                peak_x_o<=px;peak_y_o<=py;peak_z_o<=pz;seq_start_o<=ss;seq_end_o<=se;window_id_o<=wid;
            end
        end
    end
endmodule
`default_nettype wire
