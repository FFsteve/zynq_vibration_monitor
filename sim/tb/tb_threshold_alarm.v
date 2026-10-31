`timescale 1ns/1ps
`define TEST_NAME "threshold_alarm"
module tb_threshold_alarm;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,clear=0,fv=0;reg [34:0] mx=0,my=0,mz=0;
    wire [2:0] axes,rise,fall;wire any_alarm,av;
    threshold_alarm dut(.clk(clk),.rst(rst),.clear_i(clear),.feature_valid_i(fv),.ms_x_i(mx),.ms_y_i(my),.ms_z_i(mz),
        .alarm_axes_o(axes),.alarm_any_o(any_alarm),.alarm_valid_o(av),.rise_o(rise),.fall_o(fall));
    wire d0,d1;wire [31:0] e0,e1;
    stage5_alarm_parameter #(.COUNT(1)) p0(clk,d0,e0);
    stage5_alarm_parameter #(.COUNT(255)) p1(clk,d1,e1);
    `include "stage5_check.vh"
    integer file,fo,status,n=0,c,v,ea,ev,er,ef;
    reg [34:0] a,b,d;
    initial begin
        repeat(3)@(posedge clk);@(negedge clk);rst=0;
        file=$fopen("alarm_vectors.txt","r");fo=$fopen("alarm_capture.txt","w");check(file!=0 && fo!=0,"报警向量和导出文件");if(!file || !fo)finish_test;
        status=$fscanf(file,"%d %d %d %d %d %d %d %d %d\n",c,v,a,b,d,ea,ev,er,ef);
        while(status==9)begin
            @(negedge clk);clear=c;fv=v;mx=a;my=b;mz=d;
            @(posedge clk);#1;
            check(axes===ea[2:0] && av===ev[0],"滞回和连续确认与Python一致");
            check(rise===er[2:0] && fall===ef[2:0] && any_alarm==(|axes),"事件脉冲及三轴合成");
            if(c)check(!av && fall==0,"数据无效不伪造恢复事件");
            $fdisplay(fo,"%0d %0d %0d %0d",axes,av,rise,fall);n=n+1;
            status=$fscanf(file,"%d %d %d %d %d %d %d %d %d\n",c,v,a,b,d,ea,ev,er,ef);
        end
        $fclose(file);$fclose(fo);check(n==5008,"5008拍定向及随机事件");
        @(negedge clk);clear=0;fv=0;rst=1;@(posedge clk);#1;check(!av && axes==0 && rise==0 && fall==0,"复位优先");
        @(negedge clk);rst=0;fv=1;mx=35'd17179869184;my=0;mz=0;
        repeat(2)@(posedge clk);#1;check(av && axes==1,"复位后重新连续确认");
        @(negedge clk);fv=0;repeat(300)begin @(posedge clk);#1;check(axes==1 && rise==0 && fall==0,"空闲时不推进确认且脉冲不保持");end
        wait(d0 && d1);check(e0==0 && e1==0,"阈值平方2的34次方及连续1/255窗口边界");finish_test;
    end
endmodule

module stage5_alarm_parameter #(parameter integer COUNT=1)(input wire clk,output reg done=0,output reg [31:0] errors=0);
    reg rst=1,clear=0,fv=0;reg [34:0] ms=0;wire [2:0] axes,rise,fall;wire av;
    threshold_alarm #(.RMS_ON(131072),.RMS_OFF(131071),.ASSERT_WINDOWS(COUNT),.RELEASE_WINDOWS(COUNT)) dut(
        .clk(clk),.rst(rst),.clear_i(clear),.feature_valid_i(fv),.ms_x_i(ms),.ms_y_i(35'd0),.ms_z_i(35'd0),
        .alarm_axes_o(axes),.alarm_valid_o(av),.rise_o(rise),.fall_o(fall),
        .alarm_any_o());
    integer i;
    initial begin
        repeat(4)@(posedge clk);@(negedge clk);rst=0;fv=1;ms=35'd17179869184;
        for(i=1;i<=COUNT;i=i+1)begin @(posedge clk);#1;if(axes!==((i==COUNT)?3'b001:3'b000))errors=errors+1;end
        @(negedge clk);ms=35'd17179607041;
        for(i=1;i<=COUNT;i=i+1)begin @(posedge clk);#1;if(axes!==((i==COUNT)?3'b000:3'b001))errors=errors+1;end
        if(fall!==1)errors=errors+1;
        @(negedge clk);clear=1;ms=35'd17179869184;
        @(posedge clk);#1;if(av || axes!=0 || rise!=0 || fall!=0)errors=errors+1;
        @(negedge clk);clear=0;
        for(i=1;i<=COUNT;i=i+1)begin @(posedge clk);#1;if(axes!==((i==COUNT)?3'b001:3'b000))errors=errors+1;end
        done=1;
    end
endmodule
`undef TEST_NAME
