`timescale 1ns/1ps
`default_nettype none
// 可施加同步复位的通信核心；诊断计数只反映当前复位周期内的活动。
module monitor_core #(
    parameter integer CLK_HZ=50_000_000, BAUD=115_200,
    parameter integer BYTE_TIMEOUT_CLKS=100_000,
    parameter integer ACK_ONLY=0,QUEUE_DEPTH=4
) (
    input wire clk,rst,pl_rx,
    output wire pl_tx,
    output wire [7:0] seq_o,
    output wire signed [15:0] x_o,y_o,z_o,
    output wire frame_valid_o,
    output reg [31:0] rx_frame_count_o,uart_error_count_o,checksum_error_count_o,
                       timeout_count_o,seq_error_count_o,
    output wire [31:0] accepted_count_o,dropped_count_o,completed_count_o
);
    wire [7:0] rx_data,tx_data;
    wire rx_valid,rx_error,rx_busy,checksum_error,timeout_event,seq_error;
    wire tx_valid,tx_ready,tx_done,tx_busy,overflow,packet_done;
    wire [31:0] queued;
    uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_rx (
        .clk(clk),.rst(rst),.rx_i(pl_rx),.data_o(rx_data),.valid_o(rx_valid),
        .framing_error_o(rx_error),.busy_o(rx_busy));
    packet_parser #(.BYTE_TIMEOUT_CLKS(BYTE_TIMEOUT_CLKS)) u_parser (
        .clk(clk),.rst(rst),.byte_i(rx_data),.byte_valid_i(rx_valid),.byte_error_i(rx_error),
        .seq_o(seq_o),.x_o(x_o),.y_o(y_o),.z_o(z_o),.frame_valid_o(frame_valid_o),
        .checksum_error_o(checksum_error),.timeout_o(timeout_event),.seq_error_o(seq_error));
    return_controller #(.ACK_ONLY(ACK_ONLY),.QUEUE_DEPTH(QUEUE_DEPTH)) u_return (
        .clk(clk),.rst(rst),.frame_valid_i(frame_valid_o),.seq_i(seq_o),.x_i(x_o),.y_i(y_o),.z_i(z_o),
        .tx_data_o(tx_data),.tx_valid_o(tx_valid),.tx_ready_i(tx_ready),.tx_done_i(tx_done),
        .overflow_o(overflow),.packet_done_o(packet_done),.accepted_count_o(accepted_count_o),
        .dropped_count_o(dropped_count_o),.completed_count_o(completed_count_o),.queued_count_o(queued));
    uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_tx (
        .clk(clk),.rst(rst),.data_i(tx_data),.valid_i(tx_valid),.ready_o(tx_ready),
        .tx_o(pl_tx),.busy_o(tx_busy),.done_o(tx_done));
    always @(posedge clk)begin
        if(rst)begin rx_frame_count_o<=0;uart_error_count_o<=0;checksum_error_count_o<=0;
            timeout_count_o<=0;seq_error_count_o<=0;end
        else begin
            if(frame_valid_o)rx_frame_count_o<=rx_frame_count_o+1'b1;
            if(rx_error)uart_error_count_o<=uart_error_count_o+1'b1;
            if(checksum_error)checksum_error_count_o<=checksum_error_count_o+1'b1;
            if(timeout_event)timeout_count_o<=timeout_count_o+1'b1;
            if(seq_error)seq_error_count_o<=seq_error_count_o+1'b1;
        end
    end
endmodule
`default_nettype wire
