`timescale 1ns/1ps
`default_nettype none
// 板载有源蜂鸣器高电平导通；独立观察报警状态，不向计算链路施加反压。
module alarm_buzzer (
    input wire clk,rst,
    input wire quality_valid_i,alarm_valid_i,
    input wire [2:0] alarm_axes_i,
    output reg beep_o
);
    always @(posedge clk) begin
        if(rst) beep_o<=1'b0;
        else beep_o<=quality_valid_i && alarm_valid_i && (|alarm_axes_i);
    end
endmodule
`default_nettype wire
