`timescale 1ns/1ps
`default_nettype none
// 配置初值由 Vivado 的寄存器 INIT 实现；这不是外部电源监测电路。
module power_on_reset #(
    parameter integer HOLD_CLKS=1024
) (
    input wire clk,
    input wire restart_i,
    output reg rst_o=1'b1
);
    function integer width_for;
        input integer n;
        integer v;
        begin v=n-1;width_for=0;while(v>0)begin width_for=width_for+1;v=v>>1;end
            if(width_for<1)width_for=1;end
    endfunction
    localparam integer W=width_for(HOLD_CLKS);
    localparam [W-1:0] LAST=HOLD_CLKS-1;
    reg [W-1:0] count=0;
    // synthesis translate_off
    initial if(HOLD_CLKS<1)begin $display("ERROR reset parameter");$finish;end
    // synthesis translate_on
    always @(posedge clk) begin
        if(restart_i)begin count<=0;rst_o<=1'b1;end
        else if(rst_o)begin
            if(count==LAST)rst_o<=1'b0;
            else count<=count+1'b1;
        end
    end
endmodule
`default_nettype wire
