`timescale 1ns/1ps
`default_nettype none
// 仅提供现有候选约束对应的三个端口；本阶段不创建外部复位引脚。
module top #(
    parameter integer CLK_HZ=50_000_000,BAUD=115_200,
    parameter integer RESET_HOLD_CLKS=1024,BYTE_TIMEOUT_CLKS=100_000,
    parameter integer ACK_ONLY=0,QUEUE_DEPTH=4
) (
    input wire clk,pl_rx,
    output wire pl_tx
);
    wire rst;
    power_on_reset #(.HOLD_CLKS(RESET_HOLD_CLKS)) u_reset (
        .clk(clk),.restart_i(1'b0),.rst_o(rst));
    monitor_core #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.BYTE_TIMEOUT_CLKS(BYTE_TIMEOUT_CLKS),
        .ACK_ONLY(ACK_ONLY),.QUEUE_DEPTH(QUEUE_DEPTH)) u_core (
        .clk(clk),.rst(rst),.pl_rx(pl_rx),.pl_tx(pl_tx),
        .seq_o(),.x_o(),.y_o(),.z_o(),.frame_valid_o(),.rx_frame_count_o(),
        .uart_error_count_o(),.checksum_error_count_o(),.timeout_count_o(),.seq_error_count_o(),
        .accepted_count_o(),.dropped_count_o(),.completed_count_o());
endmodule
`default_nettype wire
