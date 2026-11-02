`timescale 1ns/1ps
`default_nettype none

// 模块职责：单轴63抽头定点低通FIR，三轴由上层并行实例化；轴内用一套乘法/累加通路逐抽头复用。
// 输入signed17、系数signed18且含16位小数，乘积signed35，累加器signed41，默认输出signed18。
// 系数由COEFF_FILE加载；必须使用已发布的63项Q16文件，文件内容会影响综合结果而不只是仿真。
// 历史使用63项环形缓冲：写指针指向新样本槽，读指针从最新样本向旧样本逆向推进。
// 状态顺序：IDLE接纳、LOAD取历史/系数、MUL保存乘积、ACC求和，共63次，ROUND舍入并发布。
// 接纳到valid_o为190个clk周期；50MHz约3.80us，充分利用约4ms样本间隔换取较小运算资源。
// 只有ready_o为1时才能送valid_i；忙时新请求不缓存，外层负责记录过载和重建历史。
// history_full_o表示已积累63个有效历史样本；预热期间也有数值输出，但不应直接用于可信报警。

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
    // 17×18保留35位乘积，累加前再符号扩展到41位，避免Verilog表达式宽度隐式截断。
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
    // Q16累加结果先取扩位绝对值，加32768再右移16位，最后还原符号；正负半值统一远离零。
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
                    // 只把新样本定义为第一项有效历史；旧存储内容可保留，由active_count屏蔽，免去整数组复位。
                    if(restart_i) begin
                        history[0]<=data_i;wr_ptr<=1;rd_ptr<=0;
                        history_count<=1;active_count<=1;history_full_o<=0;
                    end else begin
                        history[wr_ptr]<=data_i;rd_ptr<=wr_ptr;
                        wr_ptr<=(wr_ptr==62)?0:wr_ptr+1'b1;
                        // active_count保存本次卷积应使用的历史长度，不能在运算中再跟随外部请求变化。
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
                // LOAD、MUL、ACC分开寄存，便于推断DSP并缩短组合路径；不能因语句短就假设三步同拍完成。
                MUL:begin product_reg<=sample_reg*coefficient_reg;state<=ACC;end
                ACC:begin
                    accumulator<=accumulator+$signed({{6{product_reg[34]}},product_reg});
                    if(tap==62) state<=ROUND;
                    else begin tap<=tap+1'b1;rd_ptr<=(rd_ptr==0)?62:rd_ptr-1'b1;state<=LOAD;end
                end
                // 先在宽位数中比较范围，再饱和到输出宽度；直接截低位会把溢出变成符号翻转。
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
