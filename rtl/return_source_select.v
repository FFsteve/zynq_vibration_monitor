`timescale 1ns/1ps
`default_nettype none

// 模块职责：在综合时选定原始signed16或滤波signed18回传，寄存数据与有效事件。
// 原始模式保持传感器包数值；滤波模式算术右移2位后放入原十字节布局的16位轴字段。
// 为何缩位：保留内部FIR/统计18位动态范围，同时兼容既有UART包，不改协议或添加模式位。
// PC按滤波模式乘4恢复计数尺度，但丢弃的低2位不可恢复；内部RMS/报警不使用此缩位结果。
// 算术右移对负数向负无穷取整，不能改成无符号移位或把乘4理解成无损传输。
// selected_valid_o仅在选中来源有新数据时为1，数据与SEQ同沿寄存，其他时间保持。

// 模式在综合时固定；滤波线缆计数乘4后恢复原计数尺度，内部精度不变。
module return_source_select #(parameter integer RETURN_FILTERED=0)(
    input wire clk,rst,raw_valid_i,filtered_valid_i,
    input wire [7:0] raw_seq_i,filtered_seq_i,
    input wire signed [15:0] raw_x_i,raw_y_i,raw_z_i,
    input wire signed [17:0] filtered_x_i,filtered_y_i,filtered_z_i,
    output reg selected_valid_o,
    output reg [7:0] seq_o,
    output reg signed [15:0] x_o,y_o,z_o
);
    // synthesis translate_off
    initial if(RETURN_FILTERED!=0 && RETURN_FILTERED!=1)begin $display("ERROR stage6 invalid return mode");$finish;end
    // synthesis translate_on
    always @(posedge clk)begin
        if(rst)begin selected_valid_o<=0;seq_o<=0;x_o<=0;y_o<=0;z_o<=0;end
        else begin
            selected_valid_o<=RETURN_FILTERED ? filtered_valid_i : raw_valid_i;
            // 在移位前显式$signed，确保负加速度高位补1，而不是逻辑移位补0。
            if(RETURN_FILTERED && filtered_valid_i)begin
                seq_o<=filtered_seq_i;x_o<=$signed(filtered_x_i)>>>2;
                y_o<=$signed(filtered_y_i)>>>2;z_o<=$signed(filtered_z_i)>>>2;
            end else if(!RETURN_FILTERED && raw_valid_i)begin
                seq_o<=raw_seq_i;x_o<=raw_x_i;y_o<=raw_y_i;z_o<=raw_z_i;
            end
        end
    end
endmodule
`default_nettype wire
