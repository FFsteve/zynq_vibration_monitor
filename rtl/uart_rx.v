`timescale 1ns/1ps
`default_nettype none

// 8N1 串口接收器：全部逻辑使用 clk，rx_i 是唯一的异步输入。
// rst 必须与 clk 同步，并至少覆盖一个时钟上升沿。
module uart_rx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx_i,
    output reg  [7:0] data_o,
    output reg        valid_o,
    output reg        framing_error_o,
    output wire       busy_o
);

    // 用 Verilog-2001 函数计算计数器位宽，替代 $clog2，最小位宽为 1。
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
            if (counter_width < 1)
                counter_width = 1;
        end
    endfunction

    // BAUD 非正时使用备用除数，避免先发生除零，使仿真能给出参数错误提示。
    localparam integer SAFE_BAUD    = (BAUD > 0) ? BAUD : 1;
    localparam integer BIT_CLKS     = (CLK_HZ + SAFE_BAUD / 2) / SAFE_BAUD;
    localparam integer HALF_CLKS    = BIT_CLKS / 2;
    localparam integer COUNT_WIDTH  = counter_width(BIT_CLKS);
    localparam [COUNT_WIDTH-1:0] BIT_LAST  = BIT_CLKS - 1;
    localparam [COUNT_WIDTH-1:0] HALF_LAST = HALF_CLKS - 1;

    localparam [2:0] WAIT_HIGH = 3'd0;
    localparam [2:0] IDLE      = 3'd1;
    localparam [2:0] START     = 3'd2;
    localparam [2:0] DATA      = 3'd3;
    localparam [2:0] STOP      = 3'd4;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg rx_meta;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg rx_sync;
    reg rx_prev;
    reg [2:0] state;
    reg [COUNT_WIDTH-1:0] baud_cnt;
    reg [2:0] bit_idx;
    reg [7:0] shift_reg;

    assign busy_o = (state == START) || (state == DATA) || (state == STOP);

    // synthesis translate_off
    initial begin
        if ((CLK_HZ <= 0) || (BAUD <= 0) || (BIT_CLKS < 4)) begin
            $display("ERROR uart_rx: require CLK_HZ > 0, BAUD > 0, BIT_CLKS >= 4");
            $finish;
        end
    end
    // synthesis translate_on

    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_meta <= rx_i;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state           <= WAIT_HIGH;
            baud_cnt        <= {COUNT_WIDTH{1'b0}};
            bit_idx         <= 3'd0;
            shift_reg       <= 8'h00;
            data_o          <= 8'h00;
            valid_o         <= 1'b0;
            framing_error_o <= 1'b0;
        end else begin
            valid_o         <= 1'b0;
            framing_error_o <= 1'b0;

            case (state)
                WAIT_HIGH: begin
                    // 统计连续高电平采样次数；遇到低电平就重新计数。
                    // 持续低电平期间保持等待，避免反复报告同一次线路异常。
                    if (!rx_sync)
                        baud_cnt <= {COUNT_WIDTH{1'b0}};
                    else if (baud_cnt == BIT_LAST) begin
                        baud_cnt <= {COUNT_WIDTH{1'b0}};
                        state <= IDLE;
                    end else
                        baud_cnt <= baud_cnt + 1'b1;
                end

                IDLE: begin
                    if (rx_prev && !rx_sync) begin
                        baud_cnt <= HALF_LAST;
                        state <= START;
                    end
                end

                START: begin
                    if (baud_cnt != 0)
                        baud_cnt <= baud_cnt - 1'b1;
                    else if (!rx_sync) begin
                        baud_cnt <= BIT_LAST;
                        bit_idx <= 3'd0;
                        shift_reg <= 8'h00;
                        state <= DATA;
                    end else begin
                        // 假起始位：不提交字节，也不产生停止位错误事件。
                        state <= IDLE;
                    end
                end

                DATA: begin
                    if (baud_cnt != 0)
                        baud_cnt <= baud_cnt - 1'b1;
                    else begin
                        shift_reg[bit_idx] <= rx_sync;
                        baud_cnt <= BIT_LAST;
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end
                end

                STOP: begin
                    if (baud_cnt != 0)
                        baud_cnt <= baud_cnt - 1'b1;
                    else begin
                        baud_cnt <= {COUNT_WIDTH{1'b0}};
                        if (rx_sync) begin
                            data_o <= shift_reg;
                            valid_o <= 1'b1;
                            // 在停止位中心确认成功后重新等待起始沿，
                            // 支持仅有一个停止位、无额外空闲间隔的连续字节。
                            state <= IDLE;
                        end else begin
                            framing_error_o <= 1'b1;
                            state <= WAIT_HIGH;
                        end
                    end
                end

                default: begin
                    state <= WAIT_HIGH;
                    baud_cnt <= {COUNT_WIDTH{1'b0}};
                end
            endcase
        end
    end
endmodule

`default_nettype wire
