`timescale 1ns/1ps
`define TEST_NAME "dc_remove"
module tb_dc_remove;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,valid=0,restart=0;
    reg signed [15:0] data=0;
    wire signed [16:0] output_data;wire output_valid;
    dc_remove dut(.clk(clk),.rst(rst),.sample_valid_i(valid),.restart_i(restart),.data_i(data),.data_o(output_data),.valid_o(output_valid));
    `include "stage4_check.vh"
    integer file,status,r,x,expected,unused,n=0,j;
    reg signed [31:0] saved;
    initial begin
        repeat(3)@(posedge clk);@(negedge clk);rst=0;
        file=$fopen("vectors.txt","r");check(file!=0,"向量文件存在");
        if(file==0)finish_test;
        status=$fscanf(file,"%d %d %d %d\n",r,x,expected,unused);
        while(status==4)begin
            @(negedge clk);valid=1;restart=r;data=x;
            @(posedge clk);#1;check(output_valid,"有效输入对应有效输出");
            check(output_data===expected,"去直流数值匹配独立Python参考");n=n+1;
            if(n%17==0)begin
                saved=dut.baseline_q;
                @(negedge clk);valid=0;restart=1;data=~data;
                for(j=0;j<3;j=j+1)begin @(posedge clk);#1;
                    check(!output_valid,"空闲restart不制造输出");check(dut.baseline_q===saved,"无效事件不更新基线");end
            end
            status=$fscanf(file,"%d %d %d %d\n",r,x,expected,unused);
        end
        check(n==41728,"全部41728个数值向量已评分");$fclose(file);
        @(negedge clk);rst=1;valid=1;data=32767;
        @(posedge clk);#1;check(!output_valid && output_data==0,"复位优先于输入");
        @(negedge clk);rst=0;data=-32768;restart=0;
        @(posedge clk);#1;check(output_valid && output_data==0,"复位后首次样本重建基线");
        @(negedge clk);data=32767;
        @(posedge clk);#1;check(output_data==65535,"正差值不在16位回绕");
        @(negedge clk);restart=1;data=32767;
        @(posedge clk);#1;check(output_data==0,"显式重启");
        @(negedge clk);restart=0;data=-32768;
        @(posedge clk);#1;check(output_data==-65535,"负差值不在16位回绕");
        @(negedge clk);restart=1;data=0;
        @(posedge clk);#1;check(output_data==0,"半单位测试重建零基线");
        @(negedge clk);restart=0;data=16;
        @(posedge clk);#1;check(output_data==16,"建立正半计数基线");
        @(negedge clk);data=0;
        @(posedge clk);#1;check(output_data==-1,"负半单位远离零舍入");
        @(negedge clk);restart=1;data=0;
        @(posedge clk);#1;
        @(negedge clk);restart=0;data=-16;
        @(posedge clk);#1;check(output_data==-16,"建立负半计数基线");
        @(negedge clk);data=0;
        @(posedge clk);#1;check(output_data==1,"正半单位远离零舍入");
        finish_test;
    end
endmodule
`undef TEST_NAME
