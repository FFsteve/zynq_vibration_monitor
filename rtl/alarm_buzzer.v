`timescale 1ns/1ps
`default_nettype none

// 模块职责：把可信的任一轴报警状态转成有源蜂鸣器使能，只观察主链，不产生反压或反馈。
// 输出条件为quality_valid_i && alarm_valid_i && |alarm_axes_i，三个条件必须同时成立。
// 为何不能只看报警位：复位、预热或断流后，残留数据不能继续触发声音；有效位用于主动关闭。
// 为何不能只看feature_valid或rise：它们是一拍事件，蜂鸣器需要在整个报警期间保持使能。
// 使用一个输出寄存器，避免组合变化直接驱动；核心状态变化后至多下一个时钟沿反映到beep_o。
// 本板为高有效有源驱动，输出持续高电平即可；不生成音频PWM、不占用新的时钟或主链握手。
// 单拍控制延迟在50MHz下为20ns，不代表器件声学起振时间；实际声音由用户上板确认。

// 板载有源蜂鸣器高电平导通；独立观察报警状态，不向计算链路施加反压。
module alarm_buzzer (
    input wire clk,rst,
    input wire quality_valid_i,alarm_valid_i,
    input wire [2:0] alarm_axes_i,
    output reg beep_o
);
    // 复位优先保证关闭；正常解除或质量撤销也会在下一个采样沿关断，不需要独立状态机。
    always @(posedge clk) begin
        if(rst) beep_o<=1'b0;
        else beep_o<=quality_valid_i && alarm_valid_i && (|alarm_axes_i);
    end
endmodule
`default_nettype wire
