`timescale 1ns/1ps
`default_nettype none
// 可控发送端模型用于制造反压、满队列和同拍出入队；不读取内部指针预测数据。
module tb_return_case #(parameter integer ACK=0)(
    output reg done=0,output integer error_count=0,output integer checks=0
);
    reg clk=0,rst=1,frame_valid=0,release_tx=0;
    reg [7:0] seq=0;reg [15:0] x=0,y=0,z=0;
    wire [7:0] tx_data;wire tx_valid,overflow,packet_done;
    wire [31:0] accepted,dropped,completed,queued;
    reg fake_busy=0,fake_done=0;
    integer remaining=0,cycle=0;
    wire ready=release_tx&&(cycle%7!=0)&&(!fake_busy||remaining==0);
    reg [7:0] expected[0:255];integer head=0,tail=0,i,n;
    reg old_stall=0;reg [7:0] held;
    always #10 clk=~clk;
    return_controller #(.ACK_ONLY(ACK),.QUEUE_DEPTH(2)) dut(
        .clk(clk),.rst(rst),.frame_valid_i(frame_valid),.seq_i(seq),.x_i(x),.y_i(y),.z_i(z),
        .tx_data_o(tx_data),.tx_valid_o(tx_valid),.tx_ready_i(ready),.tx_done_i(fake_done),
        .overflow_o(overflow),.packet_done_o(packet_done),.accepted_count_o(accepted),
        .dropped_count_o(dropped),.completed_count_o(completed),.queued_count_o(queued));
    task fail;input [8*100-1:0] msg;
        begin error_count=error_count+1;$display("FAIL return ACK=%0d: %0s",ACK,msg);end endtask
    task expect_sample;input [7:0] s;integer k;reg [79:0] p;reg [7:0] chk;
        begin
            // 各轴取互不相同的已知值，防止字段交换被相同数据掩盖。
            chk=s^8'h12^s^8'hff^s^8'h80^s;
            p={16'ha55a,s,8'h12,s,8'hff,s,8'h80,s,chk};
            if(ACK)begin expected[tail]=8'h06;tail=tail+1;end
            else for(k=0;k<10;k=k+1)begin expected[tail]=p[79:72];tail=tail+1;p=p<<8;end
        end
    endtask
    task drive_now;input [7:0] s;
        begin seq=s;x={8'h12,s};y={8'hff,s};z={8'h80,s};frame_valid=1;
            @(negedge clk);frame_valid=0;seq=8'hee;x=0;y=0;z=0;end
    endtask
    task drive;input [7:0] s;begin @(negedge clk);drive_now(s);end endtask
    task drained;
        begin
            n=0;while(completed!=accepted && n<2000)begin @(negedge clk);n=n+1;end
            repeat(5)@(negedge clk);checks=checks+1;
            if(n==2000 || head!=tail || queued!=0)fail("drain/count mismatch");
        end
    endtask
    always @(posedge clk)begin
        cycle=cycle+1;
        if(rst)begin fake_busy<=0;fake_done<=0;remaining<=0;old_stall=0;end
        else begin
            fake_done<=0;
            if(fake_busy)begin
                if(remaining==0)begin fake_busy<=0;fake_done<=1;end
                else remaining<=remaining-1;
            end
            if(old_stall && (!tx_valid || tx_data!==held))fail("valid/data changed under backpressure");
            if(tx_valid&&ready)begin
                checks=checks+1;
                if(head>=tail)fail("unexpected byte");
                else begin if(tx_data!==expected[head])fail("snapshot/order mismatch");head=head+1;end
                fake_busy<=1;remaining<=6;
            end
            old_stall=tx_valid&&!ready;held=tx_data;
        end
    end
    initial begin
        repeat(4)@(negedge clk);rst=0;
        expect_sample(0);drive(0);repeat(3)@(negedge clk);
        expect_sample(1);drive(1);expect_sample(2);drive(2);
        drive(3);repeat(2)@(negedge clk);
        checks=checks+1;if(accepted!=3||dropped!=1||queued!=2)fail("full queue policy incorrect");
        release_tx=1;
        // 满队列出队同拍到来新样本必须被接纳，而非误报溢出。
        while(!(dut.state==3 && fake_done && queued==2))@(negedge clk);
        expect_sample(4);drive_now(4);
        drained;
        checks=checks+1;if(accepted!=4||completed!=4||dropped!=1)fail("simultaneous pop/push failed");
        // 在阻塞期间复位，清空整个发送上下文和队列。
        release_tx=0;expect_sample(5);drive(5);repeat(5)@(negedge clk);
        rst=1;repeat(3)@(negedge clk);head=0;tail=0;rst=0;
        checks=checks+1;if(accepted!=0||dropped!=0||completed!=0||tx_valid)fail("reset did not flush");
        expect_sample(7);drive(7);expect_sample(8);drive(8);release_tx=1;
        drained;checks=checks+1;if(accepted!=2||completed!=2||dropped!=0)fail("recovery failed");
        done=1;
    end
endmodule
module tb_return_controller;
    wire a,b;wire [31:0] ea,eb,ca,cb;
    reg test_done=0;integer error_count=0,checks=0,f;
    tb_return_case #(.ACK(0)) frame_case(.done(a),.error_count(ea),.checks(ca));
    tb_return_case #(.ACK(1)) ack_case(.done(b),.error_count(eb),.checks(cb));
    initial begin wait(a&&b);#1;error_count=ea+eb;checks=ca+cb;test_done=1;
        f=$fopen("return_controller_result.txt","w");if(f==0)error_count=error_count+1;
        if(error_count==0)begin $display("PASS return_controller checks=%0d errors=0",checks);
            if(f!=0)$fdisplay(f,"PASS return_controller checks=%0d errors=0",checks);end
        else if(f!=0)$fdisplay(f,"FAIL return_controller errors=%0d",error_count);
        if(f!=0)$fclose(f);$finish;end
    initial begin #1_000_000;error_count=error_count+1;$display("FAIL return watchdog");$finish;end
endmodule
`default_nettype wire
