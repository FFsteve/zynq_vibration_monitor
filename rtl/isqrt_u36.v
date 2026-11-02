`timescale 1ns/1ps
`default_nettype none

// 模块职责：求36位无符号整数的向下取整平方根，供MS转RMS使用，不依赖实数运算。
// 输入在valid_i && ready_o时锁存；运行期间不接纳新请求，复位可取消未完成计算。
// 逐位试商算法每拍取被开方数最高两位，更新余数并决定下一位根，36位共18轮。
// shifted = 4*remainder + 下一组两位，trial = 4*root + 1；够减则本轮根位为1。
// 所有运算都有寄存器边界，避免一次性组合开方形成很长的关键路径。
// 结果满足root_o^2 <= 输入 < (root_o+1)^2，remainder_o等于输入减去root_o平方。
// valid_o是完成脉冲；root_o及remainder_o在两次完成之间保持，不能仅看数值判断是否有新结果。

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
    // 临时比较保留21位，余数左移两位时不先截断；最后按算法不变量回存19位余数。
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
                // iteration从0开始，第17轮是第18次更新；必须发布next_root，旧root还少最后一位。
                if(iteration==17) begin
                    running<=0;root_o<=next_root;remainder_o<=next_remainder[18:0];valid_o<=1;
                end else iteration<=iteration+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
