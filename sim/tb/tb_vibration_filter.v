`timescale 1ns/1ps
`define TEST_NAME "vibration_filter"
module tb_vibration_filter;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,input_valid=0;
    reg [7:0] seq=0;
    reg signed [15:0] x=0,y=0,z=0;
    wire ready,busy,ov,full,sat,overrun,restarted;
    wire [7:0] result_seq;
    wire signed [17:0] ox,oy,oz;
    wire [31:0] accepted,dropped,restarts;
    vibration_filter #(.GAP_TIMEOUT_CLKS(1000)) dut(.clk(clk),.rst(rst),.frame_valid_i(input_valid),.seq_i(seq),
        .x_i(x),.y_i(y),.z_i(z),.ready_o(ready),.busy_o(busy),.filtered_valid_o(ov),.seq_o(result_seq),
        .x_o(ox),.y_o(oy),.z_o(oz),.history_full_o(full),.saturated_o(sat),.overrun_o(overrun),
        .stream_restart_o(restarted),.accepted_count_o(accepted),.dropped_count_o(dropped),.restart_count_o(restarts));
    `include "stage4_check.vh"
    integer file,outfile,status,n=0,a,b,c,ea,eb,ec,k,count=0,cut;
    reg [31:0] saved_accepted,saved_restarts;
    task sample;
        input integer sx,sy,sz,ss,gx,gy,gz,expect_restart;
        integer j;
        begin
            @(negedge clk);check(ready && !busy,"三轴模块空闲接纳");
            x=sx;y=sy;z=sz;seq=ss;input_valid=1;
            @(posedge clk);#1;check(!ov && busy,"接纳后进入忙状态");
            check(restarted==expect_restart,"序号及断流重启判定");
            if(expect_restart || count==0)count=1;else if(count<63)count=count+1;
            @(negedge clk);input_valid=0;x=~x;y=~y;z=~z;seq=~seq;
            for(j=1;j<=193;j=j+1)begin @(posedge clk);#1;
                check(ov==(j==193),"三轴结果严格193拍提交");
                check(!overrun,"没有有效事件时不丢弃");
            end
            check(result_seq===ss[7:0],"输出保留原序号");
            check(ox===gx && oy===gy && oz===gz,"三轴数值独立且与Python一致");
            check(full==(count==63),"历史完整标志不提前");check(!sat && ready,"正常结果不饱和且恢复ready");
        end
    endtask
    initial begin
        repeat(3)@(posedge clk);@(negedge clk);rst=0;
        file=$fopen("triple_vectors.txt","r");outfile=$fopen("rtl_triple.csv","w");
        check(file!=0 && outfile!=0,"三轴向量和结果文件");if(file==0 || outfile==0)finish_test;
        $fdisplay(outfile,"index,x,y,z");
        status=$fscanf(file,"%d %d %d %d %d %d\n",a,b,c,ea,eb,ec);
        while(status==6)begin
            sample(a,b,c,(251+n)%256,ea,eb,ec,0);
            $fdisplay(outfile,"%0d,%0d,%0d,%0d",n,$signed(ox),$signed(oy),$signed(oz));n=n+1;
            status=$fscanf(file,"%d %d %d %d %d %d\n",a,b,c,ea,eb,ec);
        end
        $fclose(file);$fclose(outfile);check(n==4000,"4000组独立三轴向量及多次序号回绕");
        sample(100,200,300,7,0,0,0,1);
        sample(100,200,300,7,0,0,0,1);
        sample(100,200,300,255,0,0,0,1);
        sample(100,200,300,0,0,0,0,0);
        for(k=1;k<=64;k=k+1)sample(100,200,300,k,0,0,0,0);
        // sample 返回时距离接纳193拍；安排阈值前、阈值本身及后一拍输入。
        repeat(805)@(posedge clk);#1;sample(100,200,300,65,0,0,0,0);
        repeat(806)@(posedge clk);#1;sample(100,200,300,66,0,0,0,1);
        repeat(807)@(posedge clk);#1;sample(100,200,300,67,0,0,0,1);
        saved_accepted=accepted;saved_restarts=restarts;
        repeat(1200)begin @(posedge clk);#1;check(!ov,"断流不产生伪样本");end
        check(!full && accepted==saved_accepted && restarts==saved_restarts,"断流只使历史失效，不反复接纳或重启计数");
        sample(100,200,300,68,0,0,0,1);
        saved_accepted=accepted;
        @(negedge clk);input_valid=1;seq=69;x=10;y=20;z=30;
        @(posedge clk);#1;@(negedge clk);input_valid=0;
        for(k=1;k<=193;k=k+1)begin
            @(posedge clk);#1;
            if(k==10)begin @(negedge clk);input_valid=1;seq=70;x=32767;y=-32768;z=12345;end
            if(k==11)begin check(overrun,"忙时事件产生一次丢弃标志");@(negedge clk);input_valid=0;end
            if(k>11)check(!overrun,"丢弃标志为一拍");
        end
        check(ov && result_seq==69 && ox==0 && oy==0 && oz==0,"忙时输入不覆盖当前快照");
        check(accepted==saved_accepted+1 && dropped==1,"接纳和丢弃计数准确");
        sample(100,200,300,71,0,0,0,1);
        for(cut=1;cut<=4;cut=cut+1)begin
            @(negedge clk);input_valid=1;seq=72;x=32767;y=-32768;z=15000;
            @(posedge clk);#1;@(negedge clk);input_valid=0;
            if(cut==1)repeat(1)@(posedge clk);
            if(cut==2)repeat(2)@(posedge clk);
            if(cut==3)repeat(100)@(posedge clk);
            if(cut==4)repeat(190)@(posedge clk);
            @(negedge clk);rst=1;input_valid=1;
            @(posedge clk);#1;check(!ov && accepted==0 && dropped==0,"复位清除在途结果和计数，优先于输入");
            @(negedge clk);rst=0;input_valid=0;count=0;
            repeat(194)begin @(posedge clk);#1;check(!ov,"中途复位后无旧结果");end
            sample(100,200,300,71,0,0,0,0);
        end
        finish_test;
    end
endmodule
`undef TEST_NAME
