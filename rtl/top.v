`timescale 1ns/1ps
`default_nettype none

// 入口用途：第三阶段纯通信板级顶层，只有clk、pl_rx、pl_tx，不包含FIR、特征或蜂鸣器。
// power_on_reset统一生成复位；monitor_core执行串行接收、十字节恢复解析和整包/ACK回传。
// 保留此入口是为了能够单独复现通信基线，不能因为文件名为top就认为它是当前最终功能。
// 当前比赛蜂鸣器版本的入口是system_buzzer_top，下载文件应使用相应构建目录中的配套产物。
// 参数ACK_ONLY只改变回传形式，输入包仍是固定十字节；QUEUE_DEPTH只调整等待队列深度。
// 外部没有复位端口，不能把复位STM32当作FPGA已重新配置；这是两种不同的测试起点。

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
