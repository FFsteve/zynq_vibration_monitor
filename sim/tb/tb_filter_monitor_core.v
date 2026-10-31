`timescale 1ns/1ps
`define TEST_NAME "filter_monitor_core"
module tb_filter_monitor_core;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,rx=1;
    wire tx,ov,raw_valid,full,overrun;
    wire [7:0] fs,rs;
    wire signed [17:0] fx,fy,fz;
    wire signed [15:0] raw_x,raw_y,raw_z;
    wire [31:0] received,uart_errors,checksum_errors,timeouts,seq_errors,filter_accepted,filter_dropped;
    // 加速区保持UART比例、每4000拍一包及12ms断流关系；另并行验证50MHz默认参数。
    filter_monitor_core #(.CLK_HZ(1000000),.BAUD(100000),.BYTE_TIMEOUT_CLKS(2000),.GAP_TIMEOUT_CLKS(12000)) dut(
        .clk(clk),.rst(rst),.pl_rx(rx),.pl_tx(tx),.raw_seq_o(rs),.raw_x_o(raw_x),.raw_y_o(raw_y),.raw_z_o(raw_z),
        .raw_valid_o(raw_valid),.filtered_seq_o(fs),.filtered_x_o(fx),.filtered_y_o(fy),.filtered_z_o(fz),.filtered_valid_o(ov),
        .history_full_o(full),.overrun_o(overrun),.rx_frame_count_o(received),.uart_error_count_o(uart_errors),
        .checksum_error_count_o(checksum_errors),.timeout_count_o(timeouts),.seq_error_count_o(seq_errors),
        .filter_accepted_count_o(filter_accepted),.filter_dropped_count_o(filter_dropped));
    wire default_done;wire [31:0] default_errors;
    stage4_default_smoke default_case(.clk(clk),.done(default_done),.errors(default_errors));
    `include "stage4_check.vh"
    reg [7:0] expected_bytes[0:8191];
    integer expected_x[0:1023],expected_y[0:1023],expected_z[0:1023],expected_seq[0:1023];
    integer byte_total=0,byte_seen=0,frame_total=0,frame_seen=0,file,status,n=0,a,b,c,ea,eb,ec,k,bit_index,cut,jj;
    reg [7:0] decoded;
    reg [79:0] truncated_packet;
    function [79:0] packet;
        input [7:0] s;input [15:0] x,y,z;reg [7:0] chk;
        begin chk=s^x[15:8]^x[7:0]^y[15:8]^y[7:0]^z[15:8]^z[7:0];packet={16'ha55a,s,x,y,z,chk};end
    endfunction
    task expect_frame;
        input integer s,x,y,z,gx,gy,gz;
        reg [79:0] p;integer j;
        begin
            p=packet(s,x,y,z);
            for(j=0;j<10;j=j+1)begin expected_bytes[byte_total]=p[79:72];byte_total=byte_total+1;p={p[71:0],8'd0};end
            expected_seq[frame_total]=s & 255;expected_x[frame_total]=gx;
            expected_y[frame_total]=gy;expected_z[frame_total]=gz;frame_total=frame_total+1;
        end
    endtask
    task send_byte;
        input [7:0] value;input bad_stop;integer j;
        begin
            @(negedge clk);rx=0;repeat(10)@(negedge clk);
            for(j=0;j<8;j=j+1)begin rx=value[j];repeat(10)@(negedge clk);end
            rx=!bad_stop;repeat(10)@(negedge clk);rx=1;
        end
    endtask
    task send_packet;
        input integer s,x,y,z,mode;
        reg [79:0] p;integer j;
        begin
            p=packet(s,x,y,z);
            if(mode==1)p[0]=!p[0];
            if(mode==2)p[79:72]=0;
            for(j=0;j<10;j=j+1)begin send_byte(p[79:72],0);p={p[71:0],8'd0};end
        end
    endtask
    // 独立按位时间读取输出，不利用发送器内部状态或其done作为解码依据。
    initial forever begin
        @(negedge tx);
        if(!rst)begin
            #100;check(tx===0,"回传起始位");
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin #200;decoded[bit_index]=tx;end
            #200;check(tx===1,"回传停止位");
            check(byte_seen<byte_total,"无多余原始回传字节");
            if(byte_seen<byte_total)check(decoded===expected_bytes[byte_seen],"原始十字节回传保持不变");
            byte_seen=byte_seen+1;
        end
    end
    always @(posedge clk)begin #1;
        if(!rst)begin
            check(!overrun && filter_dropped==0,"合法UART负载不使滤波支路过载");
            if(ov)begin
                check(frame_seen<frame_total,"无额外滤波结果");
                if(frame_seen<frame_total)begin
                    check(fs===expected_seq[frame_seen][7:0],"滤波输出SEQ匹配");
                    check(fx===expected_x[frame_seen] && fy===expected_y[frame_seen] && fz===expected_z[frame_seen],"UART至三轴滤波独立期望");
                end
                frame_seen=frame_seen+1;
            end
        end
    end
    initial begin
        repeat(20)@(posedge clk);@(negedge clk);rst=0;
        repeat(20)@(posedge clk);
        file=$fopen("link_vectors.txt","r");check(file!=0,"集成向量文件");if(file==0)finish_test;
        status=$fscanf(file,"%d %d %d %d %d %d\n",a,b,c,ea,eb,ec);
        while(status==6)begin
            expect_frame((251+n)%256,a,b,c,ea,eb,ec);
            send_packet((251+n)%256,a,b,c,0);
            // 十字节各100拍，调用间有1拍，余下2990拍合为约4000拍间隔。
            repeat(2990)@(posedge clk);
            n=n+1;status=$fscanf(file,"%d %d %d %d %d %d\n",a,b,c,ea,eb,ec);
        end
        $fclose(file);repeat(2000)@(posedge clk);
        check(n==600 && frame_seen==600 && byte_seen==6000,"600包及两个以上SEQ回绕");
        expect_frame(200,-23206,23205,-32768,0,0,0);send_packet(200,-23206,23205,-32768,0);
        repeat(2990)@(posedge clk);
        expect_frame(210,-32768,32767,32767,0,0,0);send_packet(210,-32768,32767,32767,0);
        repeat(2990)@(posedge clk);
        check(frame_seen==602 && byte_seen==6020,"载荷含A55A/5AA5和有符号极值仍原子解析");
        send_packet(83,123,456,-789,1);
        send_packet(84,123,456,-789,2);
        for(cut=1;cut<=9;cut=cut+1)begin
            truncated_packet=packet(90+cut,16'd17,16'd18,16'd19);
            for(jj=0;jj<cut;jj=jj+1)begin send_byte(truncated_packet[79:72],0);truncated_packet={truncated_packet[71:0],8'd0};end
            repeat(2500)@(posedge clk);
            check(frame_seen==frame_total,"各截断位置不产生滤波样本");
        end
        send_byte(8'h00,1);repeat(100)@(posedge clk);
        repeat(14000)@(posedge clk);
        expect_frame(80,17,18,19,0,0,0);send_packet(80,17,18,19,0);
        repeat(2990)@(posedge clk);
        expect_frame(81,17,18,19,0,0,0);send_packet(81,17,18,19,0);
        repeat(2990)@(posedge clk);
        check(checksum_errors>0 && uart_errors>0 && timeouts>=9,"坏校验、停止位错误及九处截断均被覆盖");
        check(frame_seen==604 && byte_seen==6040,"错误流后恢复且坏帧未推进滤波");
        @(negedge clk);rst=1;repeat(3)@(posedge clk);@(negedge clk);rst=0;
        repeat(20)@(posedge clk);
        expect_frame(9,17,18,19,0,0,0);send_packet(9,17,18,19,0);
        repeat(2990)@(posedge clk);
        check(frame_seen==605 && byte_seen==6050 && received==1,"集成复位后恢复");
        wait(default_done);check(default_errors==0,"默认50MHz与115200串口参数自检");
        finish_test;
    end
endmodule

// 默认参数通道不加速：检查原始回包、三轴恒定偏置及FF到00回绕。
module stage4_default_smoke(input wire clk,output reg done=0,output reg [31:0] errors=0);
    reg rst=1,rx=1;wire tx,ov;wire [7:0] seq;
    wire signed [17:0] x,y,z;
    wire [31:0] drops;
    filter_monitor_core dut(.clk(clk),.rst(rst),.pl_rx(rx),.pl_tx(tx),.filtered_valid_o(ov),
        .filtered_seq_o(seq),.filtered_x_o(x),.filtered_y_o(y),.filtered_z_o(z),.filter_dropped_count_o(drops));
    integer n,j,b,seen=0,out_seen=0;reg [79:0] p;reg [7:0] value;
    function [79:0] expected_packet;
        input integer index;reg [7:0] s;
        begin s=(254+index)%256;expected_packet={16'ha55a,s,16'h0001,16'hffff,16'h8000,(s^8'h81)};end
    endfunction
    task byte_send;
        input [7:0] v;integer k;
        begin @(negedge clk);rx=0;repeat(434)@(negedge clk);
            for(k=0;k<8;k=k+1)begin rx=v[k];repeat(434)@(negedge clk);end
            rx=1;repeat(434)@(negedge clk);end
    endtask
    reg [79:0] expected;
    initial forever begin
        @(negedge tx);if(!rst)begin
            #4340;if(tx!==0)errors=errors+1;
            for(b=0;b<8;b=b+1)begin #8680;value[b]=tx;end
            #8680;if(tx!==1)errors=errors+1;
            expected=expected_packet(seen/10);
            expected=expected >> (8*(9-(seen%10)));
            if(value!==expected[7:0])errors=errors+1;seen=seen+1;
        end
    end
    always @(posedge clk)begin #1;if(!rst && ov)begin
        if(x!==0 || y!==0 || z!==0 || seq!==((254+out_seen)%256))errors=errors+1;
        out_seen=out_seen+1;
    end end
    initial begin
        repeat(20)@(posedge clk);@(negedge clk);rst=0;repeat(500)@(posedge clk);
        for(n=0;n<3;n=n+1)begin
            p=expected_packet(n);
            for(j=0;j<10;j=j+1)begin byte_send(p[79:72]);p={p[71:0],8'd0};end
            repeat(156590)@(posedge clk);
        end
        if(seen!=30 || out_seen!=3 || drops!=0)errors=errors+1;
        done=1;
    end
endmodule
`undef TEST_NAME
