`timescale 1ns/1ps
`default_nettype none

// 十字节包解析器：逐字节滑动搜索；只有完整校验成功才原子提交三轴。
module packet_parser #(
    parameter integer BYTE_TIMEOUT_CLKS = 100_000
) (
    input  wire               clk,
    input  wire               rst,
    input  wire [7:0]         byte_i,
    input  wire               byte_valid_i,
    input  wire               byte_error_i,
    output reg  [7:0]         seq_o,
    output reg signed [15:0]  x_o,
    output reg signed [15:0]  y_o,
    output reg signed [15:0]  z_o,
    output reg                frame_valid_o,
    output reg                checksum_error_o,
    output reg                timeout_o,
    output reg                seq_error_o
);
    function integer counter_width;
        input integer count;
        integer value;
        begin
            value = count - 1;
            counter_width = 0;
            while (value > 0) begin
                counter_width = counter_width + 1;
                value = value >> 1;
            end
            if (counter_width < 1) counter_width = 1;
        end
    endfunction

    localparam integer COUNT_WIDTH = counter_width(BYTE_TIMEOUT_CLKS);
    localparam [COUNT_WIDTH-1:0] TIMEOUT_LAST = BYTE_TIMEOUT_CLKS - 1;
    reg [79:0] window_reg;
    reg [3:0] fill_count;
    reg [COUNT_WIDTH-1:0] gap_cnt;
    reg have_seq;
    wire [79:0] candidate = {window_reg[71:0], byte_i};
    wire [7:0] candidate_chk = candidate[63:56] ^ candidate[55:48] ^
                               candidate[47:40] ^ candidate[39:32] ^
                               candidate[31:24] ^ candidate[23:16] ^
                               candidate[15:8];
    wire header_match = (candidate[79:64] == 16'ha55a);
    wire checksum_match = (candidate_chk == candidate[7:0]);
    wire expired = (fill_count != 0) && (gap_cnt == TIMEOUT_LAST);
    wire [7:0] expected_seq = seq_o + 8'd1;

    // synthesis translate_off
    initial begin
        if (BYTE_TIMEOUT_CLKS < 2) begin
            $display("ERROR packet_parser: BYTE_TIMEOUT_CLKS must be >= 2");
            $finish;
        end
    end
    // synthesis translate_on

    always @(posedge clk) begin
        if (rst) begin
            window_reg <= 0;
            fill_count <= 0;
            gap_cnt <= 0;
            have_seq <= 1'b0;
            seq_o <= 0;
            x_o <= 0;
            y_o <= 0;
            z_o <= 0;
            frame_valid_o <= 1'b0;
            checksum_error_o <= 1'b0;
            timeout_o <= 1'b0;
            seq_error_o <= 1'b0;
        end else begin
            frame_valid_o <= 1'b0;
            checksum_error_o <= 1'b0;
            timeout_o <= 1'b0;
            seq_error_o <= 1'b0;

            if (byte_error_i) begin
                // 错误优先：同拍有效字节也丢弃，但保留最近合法样本和序号。
                window_reg <= 0;
                fill_count <= 0;
                gap_cnt <= 0;
            end else if (expired) begin
                // 边界到达的新字节只作为新窗口首字节，不拼接到过期数据。
                timeout_o <= 1'b1;
                window_reg <= byte_valid_i ? {72'd0, byte_i} : 80'd0;
                fill_count <= byte_valid_i ? 4'd1 : 4'd0;
                gap_cnt <= 0;
            end else if (byte_valid_i) begin
                gap_cnt <= 0;
                if ((fill_count >= 9) && header_match && checksum_match) begin
                    seq_o <= candidate[63:56];
                    x_o <= candidate[55:40];
                    y_o <= candidate[39:24];
                    z_o <= candidate[23:8];
                    frame_valid_o <= 1'b1;
                    seq_error_o <= have_seq && (candidate[63:56] != expected_seq);
                    have_seq <= 1'b1;
                    // 合法包已提交，清空缓存，包间正常空闲不报告超时。
                    window_reg <= 0;
                    fill_count <= 0;
                end else begin
                    window_reg <= candidate;
                    if (fill_count < 10) fill_count <= fill_count + 1'b1;
                    if ((fill_count >= 9) && header_match)
                        checksum_error_o <= 1'b1;
                end
            end else if (fill_count != 0) begin
                gap_cnt <= gap_cnt + 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
