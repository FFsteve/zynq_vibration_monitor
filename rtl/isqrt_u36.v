`timescale 1ns/1ps
`default_nettype none
// 每拍消费两位，18拍得到无符号整数平方根及精确余数。
module isqrt_u36(
    input wire clk,rst,valid_i,
    input wire [35:0] radicand_i,
    output wire ready_o,
    output reg valid_o,
    output reg [17:0] root_o,
    output reg [18:0] remainder_o
);
    reg running;
    reg [35:0] digits;
    reg [17:0] root;
    reg [18:0] remainder;
    reg [4:0] iteration;
    wire [20:0] shifted={remainder,digits[35:34]};
    wire [20:0] trial={1'b0,root,2'b01};
    wire take_bit=(shifted>=trial);
    wire [20:0] next_remainder=take_bit ? shifted-trial : shifted;
    wire [17:0] next_root={root[16:0],take_bit};
    assign ready_o=!rst && !running;
    always @(posedge clk) begin
        if(rst) begin
            running<=0;digits<=0;root<=0;remainder<=0;iteration<=0;
            valid_o<=0;root_o<=0;remainder_o<=0;
        end else begin
            valid_o<=0;
            if(!running) begin
                if(valid_i) begin
                    digits<=radicand_i;root<=0;remainder<=0;iteration<=0;running<=1;
                end
            end else begin
                digits<={digits[33:0],2'b00};root<=next_root;remainder<=next_remainder[18:0];
                if(iteration==17) begin
                    running<=0;root_o<=next_root;remainder_o<=next_remainder[18:0];valid_o<=1;
                end else iteration<=iteration+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
