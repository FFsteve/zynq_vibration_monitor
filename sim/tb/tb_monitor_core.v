`timescale 1ns/1ps
`default_nettype none
module tb_monitor_core;
    wire done;wire [31:0] errors,case_checks;
    reg test_done=0;integer error_count=0,checks=0,f;
    stage3_serial_case #(.USE_TOP(0),.ACK(0)) core_case(.done(done),.error_count(errors),.checks(case_checks));
    initial begin wait(done);#1;error_count=errors;checks=case_checks;test_done=1;
        f=$fopen("monitor_core_result.txt","w");if(f==0)error_count=error_count+1;
        if(error_count==0)begin $display("PASS monitor_core checks=%0d errors=0",checks);
            if(f!=0)$fdisplay(f,"PASS monitor_core checks=%0d errors=0",checks);end
        else if(f!=0)$fdisplay(f,"FAIL monitor_core errors=%0d",error_count);
        if(f!=0)$fclose(f);$finish;end
    initial begin #200_000_000;error_count=error_count+1;$display("FAIL core watchdog");$finish;end
endmodule
`default_nettype wire
