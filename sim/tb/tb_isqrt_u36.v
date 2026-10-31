`timescale 1ns/1ps
`define TEST_NAME "isqrt_u36"
module tb_isqrt_u36;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,valid=0;reg [35:0] value=0;
    wire ready,ov;wire [17:0] root;wire [18:0] remainder;
    isqrt_u36 dut(.clk(clk),.rst(rst),.valid_i(valid),.radicand_i(value),.ready_o(ready),.valid_o(ov),.root_o(root),.remainder_o(remainder));
    `include "stage5_check.vh"
    integer file,status,n=0,j,k;
    reg [35:0] input_value;reg [17:0] expected_root;reg [18:0] expected_remainder;
    reg [63:0] wide_value,wide_root;
    task run_one;
        input [35:0] a;input [17:0] r;input [18:0] rem;
        begin
            @(negedge clk);check(ready,"请求接纳前ready");valid=1;value=a;
            @(posedge clk);#1;check(!ready && !ov,"接纳沿不提前输出");
            @(negedge clk);valid=0;
            for(j=1;j<=18;j=j+1)begin
                // 忙时的脉冲以及输入变化不能污染已锁存的运算。
                value=~a;valid=(j==7);
                @(posedge clk);#1;
                if(j<18)check(!ov && !ready,"18拍前保持忙");
                else begin
                    check(ov && ready && root===r && remainder===rem,"整数根及余数与独立math.isqrt一致");
                    wide_value=a;wide_root=root;
                    check(wide_root*wide_root<=wide_value && (wide_root+1)*(wide_root+1)>wide_value,"平方根不等式");
                    check(wide_value-wide_root*wide_root==remainder,"精确余数");
                end
                @(negedge clk);valid=0;
            end
            @(posedge clk);#1;check(!ov,"结果有效仅一拍");
        end
    endtask
    initial begin
        repeat(3)@(posedge clk);@(negedge clk);rst=0;
        file=$fopen("sqrt_vectors.txt","r");check(file!=0,"开方向量存在");if(!file)finish_test;
        status=$fscanf(file,"%d %d %d\n",input_value,expected_root,expected_remainder);
        while(status==3)begin
            run_one(input_value,expected_root,expected_remainder);n=n+1;
            status=$fscanf(file,"%d %d %d\n",input_value,expected_root,expected_remainder);
        end
        $fclose(file);check(n==10033,"10033组36位开方输入");
        // 每个运算阶段复位均取消旧结果，之后能重新接纳。
        for(k=0;k<18;k=k+1)begin
            @(negedge clk);valid=1;value=36'hfffffffff;
            @(posedge clk);@(negedge clk);valid=0;repeat(k)@(negedge clk);
            rst=1;@(posedge clk);#1;check(!ov && !ready,"复位优先且取消运算");
            @(negedge clk);rst=0;repeat(20)begin @(posedge clk);#1;check(!ov,"取消后无旧结果");end
            run_one(36'd9,18'd3,19'd0);
        end
        // 保持请求：首个接纳后忙期间保持第二个，最早第19拍接纳。
        @(negedge clk);valid=1;value=16;
        @(posedge clk);@(negedge clk);value=25;
        repeat(18)@(posedge clk);#1;check(ov && root==4,"保持请求不影响首结果");
        @(posedge clk);#1;check(!ready && !ov,"下一拍接纳保持的请求");
        @(negedge clk);valid=0;repeat(18)@(posedge clk);#1;
        check(ov && root==5,"保持请求的第二结果");
        finish_test;
    end
endmodule
`undef TEST_NAME
