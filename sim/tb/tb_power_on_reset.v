`timescale 1ns/1ps
`default_nettype none
module tb_power_on_reset;
    reg clk=0,restart=0,test_done=0;
    wire fast_rst,slow_rst;
    integer error_count=0,checks=0,i,f;
    always #10 clk=~clk;
    power_on_reset #(.HOLD_CLKS(1)) fast(.clk(clk),.restart_i(restart),.rst_o(fast_rst));
    power_on_reset #(.HOLD_CLKS(16)) slow(.clk(clk),.restart_i(restart),.rst_o(slow_rst));
    task check;
        input condition;
        begin checks=checks+1;if(condition!==1'b1)begin error_count=error_count+1;
            $display("FAIL power_on_reset t=%0t",$time);end end
    endtask
    task release_check;
        begin
            for(i=1;i<=20;i=i+1)begin
                @(posedge clk);#0.001;
                check(fast_rst===1'b0);check(slow_rst===(i<16));
            end
        end
    endtask
    initial begin
        #1;check(fast_rst&&slow_rst);
        release_check;
        @(negedge clk);restart=1;
        repeat(3)begin @(posedge clk);#0.001;check(fast_rst&&slow_rst);end
        @(negedge clk);restart=0;
        release_check;
        // 计时途中重新触发，应重新等待完整保持周期。
        @(negedge clk);restart=1;@(negedge clk);restart=0;
        repeat(5)@(negedge clk);
        restart=1;@(negedge clk);restart=0;
        release_check;
        test_done=1;f=$fopen("power_on_reset_result.txt","w");
        if(f==0)error_count=error_count+1;
        if(error_count==0)begin $display("PASS power_on_reset checks=%0d errors=0",checks);
            if(f!=0)$fdisplay(f,"PASS power_on_reset checks=%0d errors=0",checks);end
        else if(f!=0)$fdisplay(f,"FAIL power_on_reset errors=%0d",error_count);
        if(f!=0)$fclose(f);$finish;
    end
    initial begin #100_000;error_count=error_count+1;$display("FAIL reset watchdog");$finish;end
endmodule
`default_nettype wire
