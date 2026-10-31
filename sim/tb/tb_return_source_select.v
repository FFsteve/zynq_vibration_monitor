`timescale 1ns/1ps
`define TEST_NAME "return_source_select"
module tb_return_source_select;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,rv=0,fv=0;reg [7:0] rs=0,fs=0;
    reg signed [15:0] x=0,y=0,z=0;reg signed [17:0] fx=0,fy=0,fz=0;
    wire v0,v1;wire [7:0] s0,s1;wire signed [15:0] x0,y0,z0,x1,y1,z1;
    return_source_select #(.RETURN_FILTERED(0)) raw_dut(.clk(clk),.rst(rst),.raw_valid_i(rv),.filtered_valid_i(fv),.raw_seq_i(rs),.filtered_seq_i(fs),
        .raw_x_i(x),.raw_y_i(y),.raw_z_i(z),.filtered_x_i(fx),.filtered_y_i(fy),.filtered_z_i(fz),.selected_valid_o(v0),.seq_o(s0),.x_o(x0),.y_o(y0),.z_o(z0));
    return_source_select #(.RETURN_FILTERED(1)) fil_dut(.clk(clk),.rst(rst),.raw_valid_i(rv),.filtered_valid_i(fv),.raw_seq_i(rs),.filtered_seq_i(fs),
        .raw_x_i(x),.raw_y_i(y),.raw_z_i(z),.filtered_x_i(fx),.filtered_y_i(fy),.filtered_z_i(fz),.selected_valid_o(v1),.seq_o(s1),.x_o(x1),.y_o(y1),.z_o(z1));
    `include "stage6_check.vh"
    integer file,status,n=0,a,b,c,ea,eb,ec;reg [7:0] prev0,prev1;
    initial begin
        repeat(3)@(posedge clk);@(negedge clk);rst=0;
        file=$fopen("selector_vectors.txt","r");check(file!=0,"选择器向量存在");if(!file)finish_test;
        status=$fscanf(file,"%d %d %d %d %d %d\n",a,b,c,ea,eb,ec);
        while(status==6)begin
            @(negedge clk);fx=a;fy=b;fz=c;x=a;y=b;z=c;rs=n;fs=255-n;
            rv=(n%3!=0);fv=1;prev0=s0;prev1=s1;
            @(posedge clk);#1;
            check(v0===rv && v1===fv,"只按所选支路发布事件");
            if(rv)check(s0===rs && x0===x && y0===y && z0===z,"原始数据及三轴快照不变");else check(s0===prev0,"原始无效拍保持数据");
            if(fv)check(s1===fs && x1===ea && y1===eb && z1===ec,"signed18全范围算术右移");else check(s1===prev1,"滤波无效拍保持数据");
            n=n+1;status=$fscanf(file,"%d %d %d %d %d %d\n",a,b,c,ea,eb,ec);
        end
        $fclose(file);check(n==262144,"全部18位值覆盖");
        @(negedge clk);rv=1;fv=0;prev1=s1;
        @(posedge clk);#1;check(v0 && !v1 && s1===prev1,"未选支路事件不污染滤波数据");
        @(negedge clk);rst=1;rv=1;fv=1;
        @(posedge clk);#1;check(!v0 && !v1 && s0==0 && s1==0 && x0==0 && x1==0,"复位优先并清数据");
        @(negedge clk);rst=0;rv=1;fv=1;x=-32768;fx=-131072;fy=131071;fz=-1;
        @(posedge clk);#1;check(v0 && v1 && x0==-32768 && x1==-32768 && y1==32767 && z1==-1,"复位后极值恢复");
        finish_test;
    end
endmodule
`undef TEST_NAME
