`timescale 1ns/1ps
`default_nettype none

// 仅供仿真的模块链路；没有板卡端口约束、PS 或外部回传控制。
module tb_uart_packet_link;
    reg clk=0,rst=1,tx_valid=0,force_low=0;
    reg [7:0] tx_data=0;
    wire tx_ready,tx_line,tx_busy,tx_done;
    wire [7:0] rx_data,seq_o;
    wire rx_valid,rx_error,rx_busy;
    wire signed [15:0] x_o,y_o,z_o;
    wire frame_valid,checksum_error,timeout_event,seq_error;
    reg test_done=0;
    integer error_count=0,checks=0,frames=0,tx_bytes=0,rx_bytes=0;
    integer uart_errors=0,checksum_errors=0,timeouts=0;
    integer expected_uart_errors=0,expected_checksum_errors=0,expected_timeouts=0;
    integer head=0,tail=0,i,n,result_file;
    reg [7:0] packet[0:9];
    reg [55:0] expected[0:31];
    reg expected_gap[0:31];
    reg [7:0] last_seq=0;
    reg have_seq=0;
    reg [55:0] held_sample=0;
    always #10 clk=~clk;
    uart_tx tx_dut (
        .clk(clk),.rst(rst),.data_i(tx_data),.valid_i(tx_valid),.ready_o(tx_ready),
        .tx_o(tx_line),.busy_o(tx_busy),.done_o(tx_done)
    );
    uart_rx rx_dut (
        .clk(clk),.rst(rst),.rx_i(force_low ? 1'b0 : tx_line),
        .data_o(rx_data),.valid_o(rx_valid),.framing_error_o(rx_error),.busy_o(rx_busy)
    );
    packet_parser parser_dut (
        .clk(clk),.rst(rst),.byte_i(rx_data),.byte_valid_i(rx_valid),.byte_error_i(rx_error),
        .seq_o(seq_o),.x_o(x_o),.y_o(y_o),.z_o(z_o),.frame_valid_o(frame_valid),
        .checksum_error_o(checksum_error),.timeout_o(timeout_event),.seq_error_o(seq_error)
    );
    task fail;
        input [8*160-1:0] message;
        begin error_count=error_count+1; $display("FAIL link t=%0t: %0s",$time,message); end
    endtask
    task make_packet;
        input [7:0] seq;
        input [15:0] x,y,z;
        integer k;
        begin
            packet[0]=8'ha5;packet[1]=8'h5a;packet[2]=seq;
            packet[3]=x[15:8];packet[4]=x[7:0];packet[5]=y[15:8];packet[6]=y[7:0];
            packet[7]=z[15:8];packet[8]=z[7:0];packet[9]=0;
            for(k=2;k<=8;k=k+1) packet[9]=packet[9]^packet[k];
        end
    endtask
    task expect_packet;
        input [7:0] seq;
        input [15:0] x,y,z;
        reg [7:0] next_seq;
        begin
            next_seq=last_seq+8'd1;
            expected[tail]={seq,x,y,z}; expected_gap[tail]=have_seq && seq!=next_seq;
            tail=tail+1;last_seq=seq;have_seq=1;
        end
    endtask
    task send;
        input [7:0] value;
        begin
            @(negedge clk);tx_data=value;tx_valid=1;
            while(!tx_ready) @(negedge clk);
            @(posedge clk);#0.002;
            @(negedge clk);tx_valid=0;
        end
    endtask
    task drain;
        begin
            @(negedge clk);
            while(tx_busy) @(negedge clk);
            repeat(8) @(negedge clk);
        end
    endtask
    task emit;
        integer k;
        begin for(k=0;k<10;k=k+1) send(packet[k]); drain; end
    endtask
    task good;
        input [7:0] seq;
        input [15:0] x,y,z;
        begin make_packet(seq,x,y,z);expect_packet(seq,x,y,z);emit;end
    endtask
    task checkpoint;
        input [8*80-1:0] label;
        begin
            checks=checks+1;
            if(head!=tail) fail("missing packet");
            if(tx_bytes!=rx_bytes) fail("TX/RX byte count mismatch");
            if(uart_errors!=expected_uart_errors) fail("UART error count mismatch");
            if(checksum_errors!=expected_checksum_errors) fail("checksum count mismatch");
            if(timeouts!=expected_timeouts) fail("timeout count mismatch");
            $display("CHECK link %0s frames=%0d bytes=%0d uart=%0d checksum=%0d timeout=%0d errors=%0d",
                label,frames,rx_bytes,uart_errors,checksum_errors,timeouts,error_count);
        end
    endtask

    always @(posedge clk) begin
        if(!rst && tx_valid && tx_ready) tx_bytes=tx_bytes+1;
        #0.001;
        if(rst) held_sample=0;
        else begin
            if(rx_valid) rx_bytes=rx_bytes+1;
            if(rx_error) uart_errors=uart_errors+1;
            if(checksum_error) checksum_errors=checksum_errors+1;
            if(timeout_event) timeouts=timeouts+1;
            if(frame_valid) begin
                frames=frames+1;checks=checks+1;
                if(head>=tail) fail("unexpected packet");
                else begin
                    if({seq_o,x_o,y_o,z_o} !== expected[head]) fail("packet mismatch");
                    if(seq_error !== expected_gap[head]) fail("sequence diagnostic mismatch");
                    head=head+1;
                end
                held_sample={seq_o,x_o,y_o,z_o};
            end else if({seq_o,x_o,y_o,z_o} !== held_sample) fail("invalid packet changed sample");
        end
    end
    initial begin
        repeat(5) @(negedge clk);rst=0;
        repeat(900) @(negedge clk);
        good(8'hfe,16'h0001,16'hffff,16'h8000);
        good(8'hff,16'h7fff,16'h0000,16'h8001);
        good(8'h00,16'ha55a,16'h5aa5,16'h0001);
        checkpoint("signed data, payload header and sequence wrap");

        // 完整包后超过 2 ms 的正常空闲，不应报超时。
        repeat(120_000) @(negedge clk);
        good(8'h01,16'h1234,16'h5678,16'h9abc);
        checkpoint("normal inter-packet idle");

        make_packet(8'h02,16'h1234,16'h5678,16'h9abc);
        packet[9]=packet[9]^8'h01;expected_checksum_errors=expected_checksum_errors+1;
        emit;
        good(8'h03,16'h1111,16'h2222,16'h3333);
        checkpoint("corrupt checksum then immediate recovery");

        make_packet(8'h04,16'h1234,16'h5678,16'h9abc);
        for(n=0;n<5;n=n+1) send(packet[n]);
        drain;expected_timeouts=expected_timeouts+1;
        repeat(100_010) @(negedge clk);
        good(8'h05,16'h0102,16'h0304,16'h0506);
        checkpoint("real 2 ms truncated-packet timeout");

        // 仿真中独立拉低 RX，构造真实停止位错误；不依赖包校验模拟 UART 错误。
        make_packet(8'h06,16'h1234,16'h5678,16'h9abc);
        for(n=0;n<3;n=n+1) send(packet[n]);
        drain;
        expected_uart_errors=expected_uart_errors+1;force_low=1;
        repeat(434*20) @(negedge clk);
        force_low=0;repeat(900) @(negedge clk);
        good(8'h07,16'h1111,16'hffff,16'h8000);
        checkpoint("UART BREAK flush and high-level recovery");

        make_packet(8'h08,16'h1234,16'h5678,16'h9abc);
        for(n=0;n<5;n=n+1) send(packet[n]);
        drain;
        @(negedge clk);rst=1;have_seq=0;last_seq=0;
        repeat(5) @(negedge clk);rst=0;
        repeat(900) @(negedge clk);
        good(8'h88,16'h7fff,16'h8000,16'hffff);
        checkpoint("reset clears partial packet and sequence baseline");

        $display("LINK SUMMARY frames=%0d tx_bytes=%0d rx_bytes=%0d uart=%0d checksum=%0d timeout=%0d",
            frames,tx_bytes,rx_bytes,uart_errors,checksum_errors,timeouts);
        result_file=$fopen("uart_packet_link_result.txt","w");
        if(result_file==0) fail("cannot write result");
        test_done=1;
        if(error_count==0) begin
            $display("PASS uart_packet_link checks=%0d errors=0",checks);
            if(result_file!=0) $fdisplay(result_file,"PASS uart_packet_link checks=%0d errors=0",checks);
        end else if(result_file!=0) $fdisplay(result_file,"FAIL uart_packet_link errors=%0d",error_count);
        if(result_file!=0) $fclose(result_file);
        $finish;
    end
    initial begin #50_000_000;error_count=error_count+1;$display("FAIL link watchdog");$finish;end
endmodule
`default_nettype wire
