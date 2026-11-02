`timescale 1ns/1ps
`default_nettype none

// 模块职责：将一次字节握手转换成起始位、8个数据位和停止位，串行低位先发。
// 握手规则：仅在valid_i && ready_o的上升沿锁存data_i；没有内部请求队列。
// 若上游需要等待，必须保持valid_i和数据直到握手；忙时只打一拍valid会丢失请求。
// 状态流程：IDLE空闲高、START低一位、DATA逐位发送、STOP高一位，全部使用clk计数。
// 停止位末拍提前开放ready，使上一字节done与下一字节接纳可在同一沿发生。
// done_o表示整个字节连停止位都已发完，不能把请求握手当成线缆发送完成。
// 默认每位434拍，一字节4340拍；复位立即在时钟沿将输出拉高并中止当前字节。


// 8N1 发送器；仅在 valid_i 与 ready_o 同时为高的时钟沿锁存请求。
module uart_tx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data_i,
    input  wire       valid_i,
    output wire       ready_o,
    output reg        tx_o,
    output wire       busy_o,
    output reg        done_o
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

    localparam integer SAFE_BAUD = (BAUD > 0) ? BAUD : 1;
    localparam integer BIT_CLKS = (CLK_HZ + SAFE_BAUD / 2) / SAFE_BAUD;
    localparam integer COUNT_WIDTH = counter_width(BIT_CLKS);
    localparam [COUNT_WIDTH-1:0] BIT_LAST = BIT_CLKS - 1;
    localparam [1:0] IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg [1:0] state;
    reg [COUNT_WIDTH-1:0] baud_cnt;
    reg [2:0] bit_idx;
    // 发送前锁存完整字节；发送期间上游改变data_i不会撕裂当前帧。
    reg [7:0] data_reg;

    // STOP 的最后一拍可接收下一字节，避免插入额外空闲时钟。
    assign ready_o = !rst && ((state == IDLE) ||
                             ((state == STOP) && (baud_cnt == 0)));
    assign busy_o = (state != IDLE);

    // synthesis translate_off
    initial begin
        if ((CLK_HZ <= 0) || (BAUD <= 0) || (BIT_CLKS < 4)) begin
            $display("ERROR uart_tx: invalid clock/baud parameters");
            $finish;
        end
    end
    // synthesis translate_on

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            baud_cnt <= 0;
            bit_idx <= 0;
            data_reg <= 0;
            tx_o <= 1'b1;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state)
                IDLE: begin
                    tx_o <= 1'b1;
                    if (valid_i) begin
                        data_reg <= data_i;
                        baud_cnt <= BIT_LAST;
                        tx_o <= 1'b0;
                        state <= START;
                    end
                end
                // 计数从BIT_LAST递减到0共占BIT_CLKS拍，避免每位少一拍的边界错误。
                START: begin
                    if (baud_cnt != 0) baud_cnt <= baud_cnt - 1'b1;
                    else begin
                        tx_o <= data_reg[0];
                        bit_idx <= 0;
                        baud_cnt <= BIT_LAST;
                        state <= DATA;
                    end
                end
                // 输出寄存器只在位边界更新，位中间保持不变；D7之后才进入停止位。
                DATA: begin
                    if (baud_cnt != 0) baud_cnt <= baud_cnt - 1'b1;
                    else begin
                        baud_cnt <= BIT_LAST;
                        if (bit_idx == 7) begin
                            tx_o <= 1'b1;
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                            tx_o <= data_reg[bit_idx + 1'b1];
                        end
                    end
                end
                // 最后一个停止位结束才报告done；连续发送时busy无需拉低，ready才是接纳依据。
                STOP: begin
                    if (baud_cnt != 0) baud_cnt <= baud_cnt - 1'b1;
                    else begin
                        done_o <= 1'b1;
                        if (valid_i) begin
                            // 同拍完成上一帧并开始下一帧，busy 不必拉低。
                            data_reg <= data_i;
                            baud_cnt <= BIT_LAST;
                            tx_o <= 1'b0;
                            state <= START;
                        end else begin
                            tx_o <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end
                default: begin
                    state <= IDLE;
                    tx_o <= 1'b1;
                    baud_cnt <= 0;
                end
            endcase
        end
    end
endmodule
`default_nettype wire
