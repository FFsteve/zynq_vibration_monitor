`timescale 1ns/1ps
`default_nettype none

// 模块职责：利用FPGA配置时寄存器初值，在自由运行clk下产生高有效同步复位保持区间。
// rst_o初始为1、count为0，计满HOLD_CLKS后释放；默认1024拍在50MHz下约20.48us。
// restart_i是同步电平请求，保持高会持续清计数并保持复位；拉低后重新计满再释放。
// 为何使用计数：让下级状态机在配置后先经过统一复位，不依赖各自未定义的运行状态。
// 本模块依赖目标FPGA对寄存器INIT的支持，不是通用ASIC上电电路，也不能检测供电跌落。
// 板级把restart_i接0，STM32复位不会自动拉高该输入；传感器重启由SEQ/断流机制恢复。

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
            // count从0开始，比较HOLD_CLKS-1才能覆盖要求的周期数；HOLD_CLKS=1也可正确释放。
            if(count==LAST)rst_o<=1'b0;
            else count<=count+1'b1;
        end
    end
endmodule
`default_nettype wire
