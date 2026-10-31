`timescale 1ns/1ps
`define TEST_NAME "fir_lp_serial"
module tb_fir_lp_serial;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,valid=0,restart=0;
    reg signed [16:0] data=0;
    wire ready,nready,ov,nv,sat,nsat,full,nfull;
    wire signed [17:0] result;
    wire signed [7:0] narrow;
    fir_lp_serial dut(.clk(clk),.rst(rst),.valid_i(valid),.restart_i(restart),.data_i(data),.ready_o(ready),.data_o(result),.valid_o(ov),.saturated_o(sat),.history_full_o(full));
    fir_lp_serial #(.OUT_WIDTH(8)) short_dut(.clk(clk),.rst(rst),.valid_i(valid),.restart_i(restart),.data_i(data),.ready_o(nready),.data_o(narrow),.valid_o(nv),.saturated_o(nsat),.history_full_o(nfull));
    `include "stage4_check.vh"
    integer file,outfile,status,r,unused,x,expected,n=0,j,count=0,cut;
    task sample;
        input integer value,reset_history,golden;
        integer k,clipped;
        begin
            @(negedge clk);check(ready && nready,"串行模块空闲时接纳");valid=1;restart=reset_history;data=value;
            @(posedge clk);#1;check(!ov && !ready,"接纳沿不提前输出");
            if(reset_history)count=1;else if(count<63)count=count+1;
            @(negedge clk);valid=0;restart=0;data=~data;
            for(k=1;k<=190;k=k+1)begin
                @(posedge clk);#1;
                check(ov==(k==190) && nv==ov,"严格190拍输出且两种位宽对齐");
                if(k==44)begin @(negedge clk);valid=1;data=12345;end
                if(k==45)begin @(negedge clk);valid=0;end
            end
            check(result===golden,"完整FIR点积匹配独立期望");
            check(!sat,"18位输出不意外饱和");check(full==(count==63) && full==nfull,"历史完整标志");
            clipped=golden;if(clipped>127)clipped=127;if(clipped< -128)clipped=-128;
            check(narrow===clipped,"窄输出正负饱和");check(nsat==(golden>127 || golden< -128),"饱和标志对应输出");
        end
    endtask
    initial begin
        repeat(3)@(posedge clk);@(negedge clk);rst=0;
        file=$fopen("vectors.txt","r");outfile=$fopen("rtl_fir.csv","w");check(file!=0 && outfile!=0,"文件打开");
        if(file==0 || outfile==0)finish_test;
        $fdisplay(outfile,"index,output");
        status=$fscanf(file,"%d %d %d %d\n",r,unused,x,expected);
        while(status==4)begin sample(x,r,expected);$fdisplay(outfile,"%0d,%0d",n,$signed(result));n=n+1;
            status=$fscanf(file,"%d %d %d %d\n",r,unused,x,expected);end
        check(n==41728,"全部41728个FIR数值向量");$fclose(file);$fclose(outfile);
        // 首系数为-13，单样本32768使点积恰好为负6.5个输出单位。
        sample(32768,1,-7);sample(-32768,1,7);
        sample(32767,1,-6);sample(-32767,1,6);
        // 请求保持到ready后握手，不能在忙时重复写入历史。
        @(negedge clk);valid=1;restart=1;data=0;
        @(posedge clk);#1;
        @(negedge clk);data=32768;
        repeat(190)@(posedge clk);#1;check(ov && result==0,"忙时保持的下一请求不影响当前点积");
        @(posedge clk);#1;check(!ov && !ready,"ready后下一沿仅接纳一次保持的请求");
        @(negedge clk);valid=0;
        repeat(190)@(posedge clk);#1;check(ov && result==-7,"保持请求握手后的结果");
        // 在读、乘、加和最终舍入之前复位；不允许旧结果泄漏。
        for(cut=1;cut<=4;cut=cut+1)begin
            @(negedge clk);valid=1;restart=1;data=20000;
            @(posedge clk);#1;@(negedge clk);valid=0;
            if(cut==4)begin repeat(189)@(posedge clk);@(negedge clk);end
            else if(cut>1)begin repeat(cut-1)@(posedge clk);@(negedge clk);end
            rst=1;
            @(posedge clk);#1;check(!ov && !full,"计算途中复位取消结果");
            @(negedge clk);rst=0;count=0;
            repeat(192)begin @(posedge clk);#1;check(!ov,"复位后无旧有效结果");end
            sample(20000,1,-4);
        end
        finish_test;
    end
endmodule
`undef TEST_NAME
