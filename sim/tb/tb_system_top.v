`timescale 1ns/1ps
`define TEST_NAME "system_top"
module tb_system_top;
    wire a,b,c;wire [31:0] ea,eb,ec,ca,cb,cc;
    stage6_top_case #(.MODE(0),.ACK(0)) raw_case(a,ea,ca);
    stage6_top_case #(.MODE(1),.ACK(0)) filtered_case(b,eb,cb);
    stage6_top_case #(.MODE(0),.ACK(1)) ack_case(c,ec,cc);
    `include "stage6_check.vh"
    initial begin wait(a && b && c);checks=ca+cb+cc;check(ea==0 && eb==0 && ec==0,"真实默认UART三模式独立顶层");finish_test;end
endmodule

// 默认50MHz、115200及200000拍间隔，不采用压缩参数。
module stage6_top_case #(parameter integer MODE=0,ACK=0)(output reg done=0,output reg [31:0] errors=0,output reg [31:0] checks=0);
    reg clk=0;always #10 clk=~clk;
    reg rx=1;wire tx;
    system_top #(.RETURN_FILTERED(MODE),.ACK_ONLY(ACK),.RESET_HOLD_CLKS(16)) dut(.clk(clk),.pl_rx(rx),.pl_tx(tx));
    integer n,j,k,b,seen=0,filtered_seen=0,cycles=0,timing_file;reg [79:0] p,expected;reg [7:0] decoded;
    always @(posedge clk)cycles=cycles+1;
    task check;
        input condition;
        begin checks=checks+1;if(condition!==1'b1)errors=errors+1;end
    endtask
    function [79:0] frame;
        input integer index,filtered;reg [7:0] s;
        begin s=(254+index)%256;frame=filtered ? {16'ha55a,s,48'd0,s} : {16'ha55a,s,16'd1,16'hffff,16'h8000,(s^8'h81)};end
    endfunction
    task byte_send;
        input [7:0] value;integer i;
        begin rx=0;repeat(434)@(negedge clk);
            for(i=0;i<8;i=i+1)begin rx=value[i];repeat(434)@(negedge clk);end
            rx=1;repeat(434)@(negedge clk);end
    endtask
    initial forever begin
        @(negedge tx);if(!dut.rst)begin
            $fdisplay(timing_file,"%0d %0d",seen,cycles);
            #4340;check(tx===0);
            for(b=0;b<8;b=b+1)begin #8680;decoded[b]=tx;end
            #8680;check(tx===1);
            if(ACK)begin check(decoded===8'h06);end
            else begin expected=frame(seen/10,MODE);expected=expected>>(8*(9-(seen%10)));check(decoded===expected[7:0]);end
            seen=seen+1;
        end
    end
    always @(posedge clk)begin #1;if(!dut.rst && dut.u_core.filtered_valid_o)begin
        check(dut.u_core.filtered_x_o===0 && dut.u_core.filtered_y_o===0 && dut.u_core.filtered_z_o===0);
        filtered_seen=filtered_seen+1;
    end end
    initial begin
        if(ACK)timing_file=$fopen("top_timing_ack.txt","w");
        else if(MODE)timing_file=$fopen("top_timing_filtered.txt","w");
        else timing_file=$fopen("top_timing_raw.txt","w");
        check(timing_file!=0);
        wait(!dut.rst);repeat(500)@(negedge clk);
        for(n=0;n<3;n=n+1)begin
            p=frame(n,0);
            for(j=0;j<10;j=j+1)begin byte_send(p[79:72]);p={p[71:0],8'd0};end
            repeat(156600)@(negedge clk);
        end
        // 实际默认UART参数下的坏校验及后续恢复，不产生额外应答。
        p=frame(3,0);p[0]=!p[0];
        for(j=0;j<10;j=j+1)begin byte_send(p[79:72]);p={p[71:0],8'd0};end
        repeat(156600)@(negedge clk);
        check(dut.u_core.checksum_error_count_o>0 && seen==(ACK?3:30));
        p=frame(3,0);
        for(j=0;j<10;j=j+1)begin byte_send(p[79:72]);p={p[71:0],8'd0};end
        repeat(156600)@(negedge clk);
        check(seen==(ACK?4:40) && filtered_seen==4 && dut.u_core.completed_count_o==4 && dut.u_core.dropped_count_o==0);
        check(dut.debug_rx_frame_count_o==4 && dut.debug_completed_count_o==4);
        $fclose(timing_file);
        done=1;
    end
endmodule
`undef TEST_NAME
