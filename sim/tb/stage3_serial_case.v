`timescale 1ns/1ps
`default_nettype none
// 独立模拟 PC 的发送与接收；从串行输出解码，不借用被测 RX 作为评分器。
module stage3_serial_case #(parameter integer USE_TOP=1,ACK=0)(
    output reg done=0,output integer error_count=0,output integer checks=0
);
    localparam real BIT_NS=1.0e9/115200.0;
    reg clk=0,manual_rst=1,pl_rx=1;
    wire pl_tx,rst_active;
    wire [31:0] received,accepted,dropped,completed,uart_errors,checksum_errors,timeouts,seq_errors;
    reg [7:0] packet[0:9],expected_bytes[0:4095];
    integer head=0,tail=0,i,j,k,epoch=0,start_epoch,raw_file=0,csv_file=0;
    integer expected_frames=0,expected_uart=0,expected_checksum=0,expected_timeout=0,expected_seq=0;
    reg [7:0] decoded;
    reg [15:0] sample_x,sample_y,sample_z;
    realtime next_sample;
    always #10 clk=~clk;
    generate if(USE_TOP)begin:g_top
        top #(.RESET_HOLD_CLKS(16),.ACK_ONLY(ACK)) dut(.clk(clk),.pl_rx(pl_rx),.pl_tx(pl_tx));
        assign rst_active=dut.rst;
        assign received=dut.u_core.rx_frame_count_o;
        assign accepted=dut.u_core.accepted_count_o;
        assign dropped=dut.u_core.dropped_count_o;
        assign completed=dut.u_core.completed_count_o;
        assign uart_errors=dut.u_core.uart_error_count_o;
        assign checksum_errors=dut.u_core.checksum_error_count_o;
        assign timeouts=dut.u_core.timeout_count_o;
        assign seq_errors=dut.u_core.seq_error_count_o;
    end else begin:g_core
        assign rst_active=manual_rst;
        monitor_core #(.ACK_ONLY(ACK)) dut(.clk(clk),.rst(manual_rst),.pl_rx(pl_rx),.pl_tx(pl_tx),
            .seq_o(),.x_o(),.y_o(),.z_o(),.frame_valid_o(),.rx_frame_count_o(received),
            .uart_error_count_o(uart_errors),.checksum_error_count_o(checksum_errors),
            .timeout_count_o(timeouts),.seq_error_count_o(seq_errors),.accepted_count_o(accepted),
            .dropped_count_o(dropped),.completed_count_o(completed));
    end endgenerate
    always @(posedge rst_active)epoch=epoch+1;
    task fail;input [8*120-1:0] msg;
        begin error_count=error_count+1;$display("FAIL serial top=%0d ACK=%0d t=%0t: %0s",USE_TOP,ACK,$time,msg);end endtask
    task make_packet;input [7:0] s;input [15:0] x,y,z;integer n;
        begin packet[0]=8'ha5;packet[1]=8'h5a;packet[2]=s;
            packet[3]=x[15:8];packet[4]=x[7:0];packet[5]=y[15:8];packet[6]=y[7:0];
            packet[7]=z[15:8];packet[8]=z[7:0];packet[9]=0;
            for(n=2;n<=8;n=n+1)packet[9]=packet[9]^packet[n];end
    endtask
    task send_byte;input [7:0] value;integer n;
        begin if((^value)===1'bx)fail("unknown stimulus byte");
            pl_rx=0;#(BIT_NS);for(n=0;n<8;n=n+1)begin pl_rx=value[n];#(BIT_NS);end
            pl_rx=1;#(BIT_NS);end
    endtask
    task emit;integer n;begin for(n=0;n<10;n=n+1)send_byte(packet[n]);end endtask
    task good;input [7:0] s;input [15:0] x,y,z;integer n;
        begin make_packet(s,x,y,z);expected_frames=expected_frames+1;
            if(ACK)begin expected_bytes[tail]=8'h06;tail=tail+1;end
            else for(n=0;n<10;n=n+1)begin expected_bytes[tail]=packet[n];tail=tail+1;end
            if(csv_file!=0)$fdisplay(csv_file,"%0d,%0d,%0d,%0d",s,$signed(x),$signed(y),$signed(z));
            emit;end
    endtask
    task drain;
        // 整包回传需要 100 个串行位；留出控制与停止位余量再验收。
        begin #(BIT_NS*110);end
    endtask
    task checkpoint;input [8*80-1:0] label;
        begin drain;checks=checks+1;
            if(head!=tail)fail("missing returned bytes");
            if(received!=expected_frames||accepted!=expected_frames||completed!=expected_frames||dropped!=0)
                fail("frame/queue counters mismatch");
            if(uart_errors!=expected_uart||checksum_errors!=expected_checksum||
                timeouts!=expected_timeout||seq_errors!=expected_seq)fail("diagnostic counters mismatch");
            $display("CHECK serial top=%0d ACK=%0d %0s frames=%0d bytes=%0d errors=%0d",
                USE_TOP,ACK,label,received,head,error_count);end
    endtask
    // 一次触发解码完整字节；复位跨越该字节时丢弃该次解码。
    always @(negedge pl_tx)begin
        if(!rst_active)begin
            start_epoch=epoch;#(BIT_NS/2.0);
            if(pl_tx!==0 && epoch==start_epoch)fail("invalid TX start");
            for(k=0;k<8;k=k+1)begin #(BIT_NS);decoded[k]=pl_tx;end
            #(BIT_NS);
            if(epoch==start_epoch && !rst_active)begin
                checks=checks+1;
                if(pl_tx!==1)fail("invalid TX stop");
                if(head>=tail)fail("unexpected returned byte");
                else begin if(decoded!==expected_bytes[head])fail("returned byte/snapshot mismatch");head=head+1;end
                if(raw_file!=0)$fwrite(raw_file,"%c",decoded);
            end
        end
    end
    initial begin
        if(USE_TOP)begin
            if(ACK)begin raw_file=$fopen("top_ack_capture.bin","wb");csv_file=$fopen("top_ack_expected.csv","w");end
            else begin raw_file=$fopen("top_frame_capture.bin","wb");csv_file=$fopen("top_frame_expected.csv","w");end
            if(raw_file==0||csv_file==0)fail("cannot open capture files");
            if(csv_file!=0)$fdisplay(csv_file,"seq,x,y,z");
        end
        repeat(20)@(negedge clk);manual_rst=0;
        #(BIT_NS*3);
        // 连续 16 个样本按真实 4 ms 周期送入，检验目标 250 包/s 负载。
        next_sample=$realtime;
        for(i=0;i<16;i=i+1)begin
            if($realtime<next_sample)#(next_sample-$realtime);
            // 显式约束为 16 位，避免旧仿真器对任务实参中整数取负的差异。
            sample_x=i[15:0];sample_y=16'd0-sample_x;sample_z=16'h8000+sample_x;
            good(i[7:0],sample_x,sample_y,sample_z);
            next_sample=next_sample+4_000_000.0;
        end
        checkpoint("250 packets per second");
        make_packet(16,16'h1111,16'h2222,16'h3333);packet[9]=packet[9]^1;
        expected_checksum=expected_checksum+1;expected_seq=expected_seq+1;emit;
        good(17,16'h1111,16'h2222,16'h3333);
        make_packet(18,16'h1111,16'h2222,16'h3333);packet[0]=8'h33;emit;
        good(18,16'h1234,16'hfedc,16'h8000);
        checkpoint("bad checksum/header and recovery");
        make_packet(19,16'h1111,16'h2222,16'h3333);
        for(j=0;j<5;j=j+1)send_byte(packet[j]);
        expected_timeout=expected_timeout+1;#3_000_000;
        expected_seq=expected_seq+1;good(20,16'h0001,16'hffff,16'h8000);
        checkpoint("truncated packet timeout");
        good(21,16'h4321,16'h8765,16'h8001);
        // 输入线路错误不应破坏已经接纳、正在回传的包。
        expected_uart=expected_uart+1;pl_rx=0;#(BIT_NS*20);pl_rx=1;#(BIT_NS*3);
        good(22,16'h0002,16'hfffe,16'h7fff);
        expected_seq=expected_seq+1;good(22,16'h0003,16'hfffd,16'h8000);
        good(23,16'h0004,16'hfffc,16'h7fff);
        good(24,16'ha55a,16'h5aa5,16'h8000);
        checkpoint("BREAK, duplicate sequence and header payload");
        if(!USE_TOP)begin
            // 在回传中途复位；随后新的复位周期重新建立所有计数和序号。
            good(25,1,2,3);@(negedge pl_tx);repeat(10)@(negedge clk);
            manual_rst=1;pl_rx=1;head=tail;
            repeat(5)@(negedge clk);manual_rst=0;
            expected_frames=0;expected_uart=0;expected_checksum=0;expected_timeout=0;expected_seq=0;
            #(BIT_NS*3);good(200,16'hffff,16'h8000,16'h7fff);
            checkpoint("reset during outgoing packet then recovery");
        end
        if(raw_file!=0)$fclose(raw_file);if(csv_file!=0)$fclose(csv_file);
        $display("SERIAL SUMMARY top=%0d ACK=%0d returned=%0d checks=%0d errors=%0d",USE_TOP,ACK,head,checks,error_count);
        done=1;
    end
endmodule
`default_nettype wire
