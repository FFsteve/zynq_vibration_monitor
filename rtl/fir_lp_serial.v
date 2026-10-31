`timescale 1ns/1ps
`default_nettype none
// 每轴一套串行乘加器；63项历史按样本推进，计算阶段不接纳新历史。
module fir_lp_serial #(
    parameter integer OUT_WIDTH=18,
    parameter COEFF_FILE="fir_lp_63_q16.mem"
) (
    input wire clk,rst,valid_i,restart_i,
    input wire signed [16:0] data_i,
    output wire ready_o,
    output reg signed [OUT_WIDTH-1:0] data_o,
    output reg valid_o,saturated_o,history_full_o
);
    localparam [2:0] IDLE=0,LOAD=1,MUL=2,ACC=3,ROUND=4;
    reg [2:0] state;
    reg signed [16:0] history[0:62];
    reg signed [17:0] coeff[0:62];
    reg [5:0] wr_ptr,rd_ptr,tap;
    reg [6:0] history_count,active_count;
    reg signed [16:0] sample_reg;
    reg signed [17:0] coefficient_reg;
    reg signed [34:0] product_reg;
    reg signed [40:0] accumulator;
    reg signed [41:0] magnitude,rounded;
    localparam signed [41:0] OUTPUT_MAX=(42'sd1 <<< (OUT_WIDTH-1))-1;
    localparam signed [41:0] OUTPUT_MIN=-(42'sd1 <<< (OUT_WIDTH-1));
    assign ready_o=!rst && state==IDLE;
    initial begin
        $readmemh(COEFF_FILE,coeff);
    end
    // synthesis translate_off
    integer i,fd;
    initial begin
        if(OUT_WIDTH<2 || OUT_WIDTH>18) begin $display("ERROR fir output width");$finish;end
        fd=$fopen(COEFF_FILE,"r");
        if(fd==0) begin $display("ERROR fir coefficients missing");$finish;end
        $fclose(fd);
        #1;
        for(i=0;i<63;i=i+1) if((^coeff[i])===1'bx) begin
            $display("ERROR fir coefficient unknown index=%0d",i);$finish;
        end
    end
    // synthesis translate_on
    always @* begin
        magnitude=$signed({accumulator[40],accumulator});
        if(accumulator<0) magnitude=-magnitude;
        rounded=(magnitude+42'sd32768) >>> 16;
        if(accumulator<0) rounded=-rounded;
    end
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;wr_ptr<=0;rd_ptr<=0;tap<=0;history_count<=0;active_count<=0;
            sample_reg<=0;coefficient_reg<=0;product_reg<=0;accumulator<=0;
            data_o<=0;valid_o<=0;saturated_o<=0;history_full_o<=0;
        end else begin
            valid_o<=0;saturated_o<=0;
            case(state)
                IDLE:if(valid_i) begin
                    accumulator<=0;tap<=0;state<=LOAD;
                    if(restart_i) begin
                        history[0]<=data_i;wr_ptr<=1;rd_ptr<=0;
                        history_count<=1;active_count<=1;history_full_o<=0;
                    end else begin
                        history[wr_ptr]<=data_i;rd_ptr<=wr_ptr;
                        wr_ptr<=(wr_ptr==62)?0:wr_ptr+1'b1;
                        if(history_count<63) begin
                            history_count<=history_count+1'b1;active_count<=history_count+1'b1;
                        end else active_count<=63;
                    end
                end
                LOAD:begin
                    // 没有有效历史的项强制为0，复位时不需要清整个存储数组。
                    sample_reg<=(tap<active_count)?history[rd_ptr]:17'sd0;
                    coefficient_reg<=coeff[tap];state<=MUL;
                end
                MUL:begin product_reg<=sample_reg*coefficient_reg;state<=ACC;end
                ACC:begin
                    accumulator<=accumulator+$signed({{6{product_reg[34]}},product_reg});
                    if(tap==62) state<=ROUND;
                    else begin tap<=tap+1'b1;rd_ptr<=(rd_ptr==0)?62:rd_ptr-1'b1;state<=LOAD;end
                end
                ROUND:begin
                    if(rounded>OUTPUT_MAX) begin data_o<=OUTPUT_MAX[OUT_WIDTH-1:0];saturated_o<=1;end
                    else if(rounded<OUTPUT_MIN) begin data_o<=OUTPUT_MIN[OUT_WIDTH-1:0];saturated_o<=1;end
                    else data_o<=rounded[OUT_WIDTH-1:0];
                    history_full_o<=(active_count==63);valid_o<=1;state<=IDLE;
                end
                default:begin state<=IDLE;history_count<=0;history_full_o<=0;wr_ptr<=0;end
            endcase
        end
    end
endmodule
`default_nettype wire
