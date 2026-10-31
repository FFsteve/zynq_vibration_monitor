`timescale 1ns/1ps
`default_nettype none
// 有效样本域的一阶基线估计；输入与输出单位均为原始计数。
module dc_remove (
    input wire clk,rst,sample_valid_i,restart_i,
    input wire signed [15:0] data_i,
    output reg signed [16:0] data_o,
    output reg valid_o
);
    reg initialized;
    reg signed [31:0] baseline_q;
    wire signed [32:0] input_q=$signed({data_i[15],data_i,16'd0});
    wire signed [32:0] error_q=input_q-$signed({baseline_q[31],baseline_q});
    wire signed [32:0] next_baseline=$signed({baseline_q[31],baseline_q})+(error_q >>> 5);
    reg signed [33:0] magnitude,rounded;
    always @* begin
        magnitude=$signed({error_q[32],error_q});
        if(error_q<0) magnitude=-magnitude;
        rounded=(magnitude+34'sd32768) >>> 16;
        if(error_q<0) rounded=-rounded;
    end
    always @(posedge clk) begin
        if(rst) begin
            initialized<=0;baseline_q<=0;data_o<=0;valid_o<=0;
        end else begin
            valid_o<=0;
            if(sample_valid_i) begin
                valid_o<=1;
                if(!initialized || restart_i) begin
                    initialized<=1;baseline_q<={data_i,16'd0};data_o<=0;
                end else begin
                    baseline_q<=next_baseline[31:0];data_o<=rounded[16:0];
                end
            end
        end
    end
endmodule
`default_nettype wire
