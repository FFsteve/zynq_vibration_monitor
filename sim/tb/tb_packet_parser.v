`timescale 1ns/1ps
`default_nettype none

// 字节层自检：期望包由激励直接登记，不复用被测模块的滑动窗口算法。
module tb_packet_parser;
    localparam integer LIMIT = 32;
    reg clk=0, rst=1, byte_valid_i=0, byte_error_i=0;
    reg [7:0] byte_i=0;
    wire [7:0] seq_o;
    wire signed [15:0] x_o, y_o, z_o;
    wire frame_valid_o, checksum_error_o, timeout_o, seq_error_o;
    reg test_done=0;
    integer error_count=0, checks=0;
    integer frames=0, bad_checksums=0, timeouts=0, sequence_errors=0;
    integer expected_checksums=0, expected_timeouts=0;
    integer head=0, tail=0, result_file, i, j, k;
    reg [55:0] expected [0:511];
    reg expected_gap [0:511];
    reg [7:0] last_seq=0;
    reg have_seq=0;
    reg [55:0] held_sample=0;
    reg old_valid=0, old_checksum=0, old_timeout=0;
    reg [7:0] packet [0:9];

    always #10 clk=~clk;
    packet_parser #(.BYTE_TIMEOUT_CLKS(LIMIT)) dut (
        .clk(clk), .rst(rst), .byte_i(byte_i), .byte_valid_i(byte_valid_i),
        .byte_error_i(byte_error_i), .seq_o(seq_o), .x_o(x_o), .y_o(y_o), .z_o(z_o),
        .frame_valid_o(frame_valid_o), .checksum_error_o(checksum_error_o),
        .timeout_o(timeout_o), .seq_error_o(seq_error_o)
    );

    task fail;
        input [8*160-1:0] message;
        begin error_count=error_count+1; $display("FAIL parser t=%0t: %0s",$time,message); end
    endtask
    task make_packet;
        input [7:0] seq;
        input [15:0] x,y,z;
        integer n;
        begin
            packet[0]=8'ha5; packet[1]=8'h5a; packet[2]=seq;
            packet[3]=x[15:8]; packet[4]=x[7:0];
            packet[5]=y[15:8]; packet[6]=y[7:0];
            packet[7]=z[15:8]; packet[8]=z[7:0];
            packet[9]=0;
            for(n=2;n<=8;n=n+1) packet[9]=packet[9]^packet[n];
        end
    endtask
    task expect_packet;
        input [7:0] seq;
        input [15:0] x,y,z;
        reg [7:0] next_seq;
        begin
            next_seq=last_seq+8'd1;
            expected[tail]={seq,x,y,z};
            expected_gap[tail]=have_seq && seq!=next_seq;
            tail=tail+1; last_seq=seq; have_seq=1;
        end
    endtask
    // 调用结束时位于接收沿后的下降沿，便于准确安排超时边界。
    task push;
        input [7:0] value;
        begin
            @(negedge clk); byte_i=value; byte_valid_i=1;
            @(negedge clk); byte_valid_i=0;
        end
    endtask
    task put_now;
        input [7:0] value;
        begin
            byte_i=value; byte_valid_i=1;
            @(negedge clk); byte_valid_i=0;
        end
    endtask
    task emit_packet;
        integer n;
        begin
            for(n=0;n<10;n=n+1) begin
                @(negedge clk); byte_valid_i=1; byte_i=packet[n];
            end
            @(negedge clk); byte_valid_i=0;
        end
    endtask
    task good;
        input [7:0] seq;
        input [15:0] x,y,z;
        begin make_packet(seq,x,y,z); expect_packet(seq,x,y,z); emit_packet; end
    endtask
    task abort_window;
        begin
            @(negedge clk); byte_error_i=1;
            @(negedge clk); byte_error_i=0;
        end
    endtask
    task checkpoint;
        input [8*80-1:0] label;
        begin
            repeat(2) @(negedge clk);
            checks=checks+1;
            if(head!=tail) fail("missing expected frame");
            if(bad_checksums!=expected_checksums) fail("checksum count mismatch");
            if(timeouts!=expected_timeouts) fail("timeout count mismatch");
            $display("CHECK parser %0s frames=%0d checksum=%0d timeout=%0d errors=%0d",
                label,frames,bad_checksums,timeouts,error_count);
        end
    endtask
    task reset_parser;
        begin
            @(negedge clk); rst=1; byte_valid_i=0; byte_error_i=0;
            have_seq=0; last_seq=0;
            repeat(3) @(negedge clk);
            rst=0;
        end
    endtask

    always @(posedge clk) begin
        #0.001;
        if(rst) begin
            held_sample=0;
            if({seq_o,x_o,y_o,z_o,frame_valid_o,checksum_error_o,timeout_o,seq_error_o} !== 60'd0)
                fail("reset outputs incorrect");
        end else begin
            if((^{seq_o,x_o,y_o,z_o,frame_valid_o,checksum_error_o,timeout_o,seq_error_o})===1'bx)
                fail("unknown output");
            if((frame_valid_o && old_valid) || (checksum_error_o && old_checksum) ||
               (timeout_o && old_timeout)) fail("event wider than one clock");
            if((frame_valid_o && (checksum_error_o || timeout_o)) ||
               (checksum_error_o && timeout_o)) fail("mutually exclusive events overlap");
            if(seq_error_o && !frame_valid_o) fail("sequence event without a valid frame");
            if(frame_valid_o) begin
                checks=checks+1; frames=frames+1;
                if(head>=tail) fail("unexpected frame");
                else begin
                    if({seq_o,x_o,y_o,z_o} !== expected[head]) fail("frame data/endian mismatch");
                    if(seq_error_o !== expected_gap[head]) fail("sequence diagnostic mismatch");
                    if(expected[head][47] && !(x_o<0)) fail("X is not signed negative");
                    if(expected[head][31] && !(y_o<0)) fail("Y is not signed negative");
                    if(expected[head][15] && !(z_o<0)) fail("Z is not signed negative");
                    head=head+1;
                end
                held_sample={seq_o,x_o,y_o,z_o};
            end else if({seq_o,x_o,y_o,z_o} !== held_sample) fail("non-atomic sample update");
            if(checksum_error_o) bad_checksums=bad_checksums+1;
            if(timeout_o) timeouts=timeouts+1;
            if(seq_error_o) sequence_errors=sequence_errors+1;
        end
        old_valid=frame_valid_o; old_checksum=checksum_error_o; old_timeout=timeout_o;
    end

    initial begin
        reset_parser;
        good(8'hfe,16'h0001,16'hffff,16'h8000);
        good(8'hff,16'h7fff,16'h0000,16'h8001);
        good(8'h00,16'ha55a,16'h5aa5,16'ha55a);
        good(8'h02,16'h1234,16'hfedc,16'h0102);
        good(8'h02,16'hffff,16'hffff,16'hffff);
        checkpoint("signed extremes, headers in payload, wrap/gap/duplicate");

        // 保持字节有效连续为高，检查满速输入及连续包。
        @(negedge clk); byte_valid_i=1;
        for(i=0;i<64;i=i+1) begin
            make_packet(i[7:0],i*17,16'h8000+i,16'h7fff-i);
            expect_packet(i[7:0],i*17,16'h8000+i,16'h7fff-i);
            for(j=0;j<10;j=j+1) begin byte_i=packet[j]; @(negedge clk); end
        end
        byte_valid_i=0;
        checkpoint("one byte per clock");

        // 每个字节位置分别损坏；数据区和校验区应产生候选校验错误。
        for(i=0;i<10;i=i+1) begin
            make_packet(8'h10,16'h1234,16'h5678,16'h9abc);
            packet[i]=packet[i]^8'h01;
            if(i>=2) expected_checksums=expected_checksums+1;
            emit_packet;
            good(8'h20+i,16'h1010,16'h2020,16'h3030);
            checkpoint("corrupt each position then recover");
        end

        // 同一头字节连续出现时仍应找到后续 A5 5A。
        push(8'ha5); push(8'ha5);
        good(8'h31,16'h0102,16'h0304,16'h0506);
        checkpoint("overlapping header prefix");

        // 逐个插入或删除载荷字节，紧接合法包，不依赖超时才恢复。
        for(k=0;k<2;k=k+1) begin
            for(i=2;i<=8;i=i+1) begin
                make_packet(8'h40,16'h1234,16'h5678,16'h9abc);
                expected_checksums=expected_checksums+1;
                for(j=0;j<10;j=j+1) begin
                    if(k==0 && j==i) push(8'h77);
                    if(!(k==1 && j==i)) push(packet[j]);
                end
                good(8'h50+i,16'h0101,16'h0202,16'h0303);
                checkpoint("insert/delete then immediate valid packet");
            end
        end

        // 每个截断位置后立即发送完整合法包，覆盖跨窗口重新同步。
        for(i=1;i<=9;i=i+1) begin
            make_packet(8'h60,16'h1234,16'h5678,16'h9abc);
            for(j=0;j<i;j=j+1) push(packet[j]);
            // 仅剩单个 A5 时没有完整包头，不能计为候选校验失败。
            if(i>=2) expected_checksums=expected_checksums+1;
            good(8'h70+i,16'h1111,16'h2222,16'h3333);
            checkpoint("truncate at each position then recover");
        end

        // 小于超时阈值一拍仍允许拼接。
        make_packet(8'h80,16'h1111,16'h2222,16'h3333);
        expect_packet(8'h80,16'h1111,16'h2222,16'h3333);
        for(j=0;j<9;j=j+1) push(packet[j]);
        repeat(LIMIT-2) @(negedge clk);
        put_now(packet[9]);
        checkpoint("gap LIMIT-1 accepted");

        // 校验字节在阈值或阈值后一拍到达，均不能提交旧包。
        for(i=0;i<=1;i=i+1) begin
            make_packet(8'h81,16'h1111,16'h2222,16'h3333);
            for(j=0;j<9;j=j+1) push(packet[j]);
            expected_timeouts=expected_timeouts+1;
            repeat(LIMIT-1+i) @(negedge clk);
            put_now(packet[9]);
            good(8'h82+i,16'h4444,16'h5555,16'h6666);
            checkpoint("gap LIMIT or LIMIT+1 drops old packet");
        end

        // 超时同拍的新 A5 必须成为新窗口的首字节。
        push(8'ha5); push(8'h5a); push(8'h01);
        expected_timeouts=expected_timeouts+1;
        repeat(LIMIT-1) @(negedge clk);
        make_packet(8'h90,16'h1111,16'h2222,16'h3333);
        expect_packet(8'h90,16'h1111,16'h2222,16'h3333);
        put_now(packet[0]);
        for(j=1;j<10;j=j+1) push(packet[j]);
        checkpoint("timeout boundary retains new first byte");

        // UART 错误优先于同拍校验字节及超时，不应提交旧包。
        make_packet(8'h91,16'h1111,16'h2222,16'h3333);
        for(j=0;j<9;j=j+1) push(packet[j]);
        repeat(LIMIT-1) @(negedge clk);
        byte_error_i=1; byte_valid_i=1; byte_i=packet[9];
        @(negedge clk); byte_error_i=0; byte_valid_i=0;
        good(8'h92,16'h1111,16'h2222,16'h3333);
        checkpoint("UART error priority");

        for(i=1;i<=9;i=i+1) begin
            make_packet(8'h93,16'h1111,16'h2222,16'h3333);
            for(j=0;j<i;j=j+1) push(packet[j]);
            reset_parser;
            good(8'h94,16'h0001,16'hffff,16'h8000);
            checkpoint("reset partial frame then accept first sequence");
        end

        // 没有未完成窗口的包间空闲，不应产生超时事件。
        repeat(LIMIT*2) @(negedge clk);
        checkpoint("idle after complete packet");
        push(8'h11); expected_timeouts=expected_timeouts+1;
        repeat(LIMIT*2) @(negedge clk);
        checkpoint("garbage window times out once");
        good(8'h95,16'h0000,16'h0000,16'h0000);
        checkpoint("final recovery");

        $display("PARSER SUMMARY frames=%0d checksum=%0d timeout=%0d sequence=%0d",
            frames,bad_checksums,timeouts,sequence_errors);
        test_done=1;
        result_file=$fopen("packet_parser_result.txt","w");
        if(result_file==0) fail("cannot write result");
        if(error_count==0) begin
            $display("PASS packet_parser checks=%0d errors=0",checks);
            if(result_file!=0) $fdisplay(result_file,"PASS packet_parser checks=%0d errors=0",checks);
        end else if(result_file!=0) $fdisplay(result_file,"FAIL packet_parser errors=%0d",error_count);
        if(result_file!=0) $fclose(result_file);
        $finish;
    end
    initial begin #1_000_000; error_count=error_count+1; $display("FAIL parser watchdog"); $finish; end
endmodule
`default_nettype wire
