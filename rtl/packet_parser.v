`timescale 1ns/1ps
`default_nettype none

// 模块职责：从UART字节流中恢复固定十字节包，并原子更新序号和XYZ三轴。
// 布局固定为A5 5A SEQ XH XL YH YL ZH ZL CHK；轴值为16位补码、高字节先发。
// CHK仅异或SEQ及六个轴字节，不含包头；该规则必须与STM32编码器一致。
// 采用80位滑动窗口而非遇到A5就重启：允许载荷本身含包头，也能从插字节、丢字节后再搜索。
// fill_count描述当前收集阶段，填满后每来一字节就检查最新十字节，不需要另设重复状态机。
// 默认2ms是非空窗口中相邻字节的超时，不是整包周期；合法包间约4ms空闲不会触发它。
// 事件优先级：rst、UART错误、超时边界、新字节；坏候选不会覆盖最近一次合法三轴。
// 序号错误只作诊断，不拒绝校验正确的包；XOR并不是强校验，不能承诺检出所有损坏。


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
    // 寄存器保存最近字节历史，组合candidate把本拍byte_i接到尾部，检查时包含当前字节。
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
    // 8位加法自然按模256回绕，FF之后期望00；首个合法包由have_seq屏蔽连续性检查。
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

            // 所有事件每个普通周期先拉低，仅在对应条件成立时拉高一拍，不能作为持续状态使用。
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
                // 旧窗口已有至少9字节，加上本拍才构成完整候选；同沿提交XYZ可避免跨包混轴。
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
                    // 这里统计的是包头匹配但校验失败的候选次数，不能直接等同于实际损坏包数量。
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
