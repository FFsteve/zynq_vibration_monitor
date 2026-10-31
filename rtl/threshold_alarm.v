`timescale 1ns/1ps
`default_nettype none
// 只按完整窗口推进确认计数；数据失效清理不产生正常解除事件。
module threshold_alarm #(
    parameter integer RMS_ON=2000,RMS_OFF=1500,ASSERT_WINDOWS=2,RELEASE_WINDOWS=2
)(
    input wire clk,rst,clear_i,feature_valid_i,
    input wire [34:0] ms_x_i,ms_y_i,ms_z_i,
    output reg [2:0] alarm_axes_o,
    output wire alarm_any_o,
    output reg alarm_valid_o,
    output reg [2:0] rise_o,fall_o
);
    // 先扩展再乘，避免最大阈值的平方被32位integer截断。
    localparam [35:0] ON_WIDE=RMS_ON,OFF_WIDE=RMS_OFF;
    localparam [35:0] ON_SQUARE=ON_WIDE*ON_WIDE,OFF_SQUARE=OFF_WIDE*OFF_WIDE;
    reg [7:0] up[0:2],down[0:2];
    wire [34:0] mean[0:2];
    assign mean[0]=ms_x_i;assign mean[1]=ms_y_i;assign mean[2]=ms_z_i;
    assign alarm_any_o=|alarm_axes_o;
    integer a;
    // synthesis translate_off
    initial if(RMS_OFF<0 || RMS_ON<=RMS_OFF || RMS_ON>131072 || ASSERT_WINDOWS<1 || ASSERT_WINDOWS>255 || RELEASE_WINDOWS<1 || RELEASE_WINDOWS>255) begin
        $display("ERROR stage5 invalid alarm parameter");$finish;
    end
    // synthesis translate_on
    always @(posedge clk) begin
        if(rst || clear_i) begin
            alarm_axes_o<=0;alarm_valid_o<=0;rise_o<=0;fall_o<=0;
            for(a=0;a<3;a=a+1)begin up[a]<=0;down[a]<=0;end
        end else begin
            rise_o<=0;fall_o<=0;
            if(feature_valid_i) begin
                alarm_valid_o<=1;
                for(a=0;a<3;a=a+1)begin
                    if(!alarm_axes_o[a]) begin
                        down[a]<=0;
                        if({1'b0,mean[a]}>=ON_SQUARE) begin
                            if(up[a]>=ASSERT_WINDOWS-1)begin alarm_axes_o[a]<=1;rise_o[a]<=1;up[a]<=0;end
                            else up[a]<=up[a]+1'b1;
                        end else up[a]<=0;
                    end else begin
                        up[a]<=0;
                        if({1'b0,mean[a]}<=OFF_SQUARE) begin
                            if(down[a]>=RELEASE_WINDOWS-1)begin alarm_axes_o[a]<=0;fall_o[a]<=1;down[a]<=0;end
                            else down[a]<=down[a]+1'b1;
                        end else down[a]<=0;
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
