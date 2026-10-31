`timescale 1ns/1ps
`default_nettype none
module tb_top;
    wire a,b;wire [31:0] ea,eb,ca,cb;
    reg test_done=0;integer error_count=0,checks=0,f;
    stage3_serial_case #(.USE_TOP(1),.ACK(0)) frame_case(.done(a),.error_count(ea),.checks(ca));
    stage3_serial_case #(.USE_TOP(1),.ACK(1)) ack_case(.done(b),.error_count(eb),.checks(cb));
    initial begin wait(a&&b);#1;error_count=ea+eb;checks=ca+cb;test_done=1;
        f=$fopen("top_result.txt","w");if(f==0)error_count=error_count+1;
        if(error_count==0)begin $display("PASS top checks=%0d errors=0",checks);
            if(f!=0)$fdisplay(f,"PASS top checks=%0d errors=0",checks);end
        else if(f!=0)$fdisplay(f,"FAIL top errors=%0d",error_count);
        if(f!=0)$fclose(f);$finish;end
    initial begin #200_000_000;error_count=error_count+1;$display("FAIL top watchdog");$finish;end
endmodule
`default_nettype wire
