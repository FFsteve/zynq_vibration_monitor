`timescale 1ns/1ps
`default_nettype none

// 独立周期参考模型仅依赖输入握手、锁存数据和经过的时钟数。
// 不读取发送器内部状态或计数器，也不靠同源 RX 判定 TX 正确性。
module tb_uart_tx_case #(
    parameter integer CASE_ID=0,
    parameter integer BAUD=115_200
) (
    output reg done=0,
    output integer error_count=0,
    output integer checks=0,
    output integer accepted_count=0,
    output integer completed_count=0,
    output integer aborted_count=0
);
    localparam integer N=(50_000_000+BAUD/2)/BAUD;
    reg clk=0, rst=1, valid_i=0;
    reg [7:0] data_i=0;
    wire ready_o, tx_o, busy_o, done_o;
    integer cycle=0, start_cycle=0, elapsed, phase;
    integer i,j, before_count, continuous_count=0;
    reg active=0, take, expected_done, expected_tx, expected_ready, previous_done=0;
    reg [7:0] captured;
    always #10 clk=~clk;
    uart_tx #(.BAUD(BAUD)) dut (
        .clk(clk),.rst(rst),.data_i(data_i),.valid_i(valid_i),
        .ready_o(ready_o),.tx_o(tx_o),.busy_o(busy_o),.done_o(done_o)
    );
    task fail;
        input [8*160-1:0] message;
        begin error_count=error_count+1; $display("FAIL TX case=%0d t=%0t: %0s",CASE_ID,$time,message); end
    endtask
    task send;
        input [7:0] value;
        begin
            @(negedge clk); data_i=value; valid_i=1;
            while(!ready_o) @(negedge clk);
            @(posedge clk); #0.002;
            @(negedge clk); valid_i=0; data_i=~value;
        end
    endtask
    task wait_idle;
        begin
            @(negedge clk);
            while(busy_o) @(negedge clk);
            repeat(2) @(negedge clk);
        end
    endtask
    task checkpoint;
        input [8*80-1:0] label;
        begin
            checks=checks+1;
            $display("CHECK TX case=%0d %0s accepted=%0d completed=%0d aborted=%0d errors=%0d",
                CASE_ID,label,accepted_count,completed_count,aborted_count,error_count);
        end
    endtask

    always @(posedge clk) begin
        cycle=cycle+1;
        take=valid_i && ready_o && !rst;
        expected_done=0;
        if(rst) begin
            if(active) aborted_count=aborted_count+1;
            active=0;
        end else begin
            if(active && cycle-start_cycle==10*N) begin
                expected_done=1; completed_count=completed_count+1; active=0;
            end
            if(take) begin
                if(active) fail("accepted before previous stop completed");
                if(expected_done) continuous_count=continuous_count+1;
                active=1; captured=data_i; start_cycle=cycle;
                accepted_count=accepted_count+1;
            end
        end
        elapsed=cycle-start_cycle;
        expected_tx=1;
        if(active) begin
            phase=elapsed/N;
            if(phase==0) expected_tx=0;
            else if(phase<=8) expected_tx=captured[phase-1];
        end
        expected_ready=!rst && (!active || elapsed==10*N-1);
        #0.001;
        checks=checks+1;
        if(tx_o !== expected_tx) fail("serial level or bit width mismatch");
        if(done_o !== expected_done) fail("done cycle mismatch");
        if(busy_o !== active) fail("busy mismatch");
        if(ready_o !== expected_ready) fail("ready/handshake boundary mismatch");
        if(done_o && previous_done) fail("done wider than one clock");
        previous_done=done_o;
    end

    initial begin
        repeat(4) @(negedge clk); rst=0;
        repeat(8) @(negedge clk);
        for(i=0;i<256;i=i+1) send(i[7:0]);
        wait_idle;
        if(accepted_count!=256 || completed_count!=256) fail("all-byte count mismatch");
        checkpoint("all 256 bytes, exact bits and continuous stop boundaries");

        // 接收请求后修改输入，不能影响已经锁存的帧。
        send(8'ha5);
        for(j=0;j<20;j=j+1) begin @(negedge clk); data_i=j; end
        wait_idle;
        checkpoint("input changes while busy");

        // 忙时短 valid 不会被缓存，也不能产生额外完成事件。
        send(8'h3c); before_count=accepted_count;
        @(negedge clk); valid_i=1; data_i=8'hff;
        repeat(2) @(negedge clk); valid_i=0;
        wait_idle;
        if(accepted_count!=before_count) fail("busy pulse was incorrectly queued");
        checkpoint("busy request pulse ignored");

        // valid 一直保持为高，握手后才换下一数据，检查持续反压与满吞吐。
        @(negedge clk); valid_i=1;
        for(i=0;i<64;i=i+1) begin
            data_i=8'h80+i;
            while(!ready_o) @(negedge clk);
            @(posedge clk); #0.002;
            @(negedge clk);
        end
        valid_i=0;
        wait_idle;
        checkpoint("held valid stream");

        // 在起始、各个数据位、停止位中途复位；被终止的帧不产生 done。
        for(i=0;i<=9;i=i+1) begin
            send(8'h00);
            repeat(i*N+N/4) @(negedge clk);
            rst=1;
            repeat(3) @(negedge clk); rst=0;
            send(8'h80+i);
            wait_idle;
        end
        checkpoint("reset at every serial phase then recover");

        // 复位期间 valid 为高不握手；释放后该请求只被接收一次。
        @(negedge clk); rst=1; valid_i=1; data_i=8'h5a;
        repeat(3) @(negedge clk); rst=0;
        @(posedge clk); #0.002;
        @(negedge clk); valid_i=0;
        wait_idle;
        if(accepted_count!=343 || completed_count!=333 || aborted_count!=10)
            fail("final accepted/completed/aborted count mismatch");
        if(continuous_count<250) fail("back-to-back acceptance not exercised");
        checkpoint("final counts and reset priority");
        done=1;
    end
endmodule

module tb_uart_tx;
    wire main_done,odd_done;
    wire [31:0] main_errors,odd_errors,main_checks,odd_checks;
    wire [31:0] main_accepted,odd_accepted,main_completed,odd_completed,main_aborted,odd_aborted;
    reg test_done=0;
    integer error_count=0,checks=0,result_file;
    tb_uart_tx_case #(.CASE_ID(0),.BAUD(115_200)) main_case (
        .done(main_done),.error_count(main_errors),.checks(main_checks),
        .accepted_count(main_accepted),.completed_count(main_completed),.aborted_count(main_aborted)
    );
    tb_uart_tx_case #(.CASE_ID(1),.BAUD(1_500_000)) odd_case (
        .done(odd_done),.error_count(odd_errors),.checks(odd_checks),
        .accepted_count(odd_accepted),.completed_count(odd_completed),.aborted_count(odd_aborted)
    );
    initial begin
        wait(main_done && odd_done); #1;
        error_count=main_errors+odd_errors; checks=main_checks+odd_checks;
        $display("TX SUMMARY accepted=%0d completed=%0d aborted=%0d",
            main_accepted+odd_accepted,main_completed+odd_completed,main_aborted+odd_aborted);
        result_file=$fopen("uart_tx_result.txt","w");
        if(result_file==0) error_count=error_count+1;
        test_done=1;
        if(error_count==0) begin
            $display("PASS uart_tx checks=%0d errors=0",checks);
            if(result_file!=0) $fdisplay(result_file,"PASS uart_tx checks=%0d errors=0",checks);
        end else if(result_file!=0) $fdisplay(result_file,"FAIL uart_tx errors=%0d",error_count);
        if(result_file!=0) $fclose(result_file);
        $finish;
    end
    initial begin #100_000_000; error_count=error_count+1; $display("FAIL TX watchdog"); $finish; end
endmodule
`default_nettype wire
