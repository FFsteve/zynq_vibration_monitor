`timescale 1ns/1ps
`define TEST_NAME "feature_monitor_core"
module tb_feature_monitor_core;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,rx=1;wire tx,raw_valid,filtered_valid,full,quality,fv,av,any_alarm,wo,wd;
    wire [7:0] raw_seq,fs,ss,se;wire signed [17:0] fx,fy,fz;
    wire [34:0] mx,my,mz;wire [17:0] rmsx,rmsy,rmsz,px,py,pz;
    wire [31:0] wid,received,uart_errors,checksum_errors,timeouts,seq_errors,waccept,wdrop,aborts;
    wire [2:0] axes,rise,fall;
    // 时间压缩50倍：4000拍/包，超时和UART位时间同比例；另测真实默认UART。
    feature_monitor_core #(.CLK_HZ(1000000),.BAUD(100000),.BYTE_TIMEOUT_CLKS(2000),.GAP_TIMEOUT_CLKS(12000)) dut(
        .clk(clk),.rst(rst),.pl_rx(rx),.pl_tx(tx),.raw_valid_o(raw_valid),.filtered_valid_o(filtered_valid),.history_full_o(full),.quality_valid_o(quality),
        .raw_seq_o(raw_seq),.filtered_seq_o(fs),.filtered_x_o(fx),.filtered_y_o(fy),.filtered_z_o(fz),.feature_valid_o(fv),
        .ms_x_o(mx),.ms_y_o(my),.ms_z_o(mz),.rms_x_o(rmsx),.rms_y_o(rmsy),.rms_z_o(rmsz),.peak_x_o(px),.peak_y_o(py),.peak_z_o(pz),
        .seq_start_o(ss),.seq_end_o(se),.window_id_o(wid),.alarm_axes_o(axes),.alarm_any_o(any_alarm),.alarm_valid_o(av),.alarm_rise_o(rise),.alarm_fall_o(fall),
        .window_overrun_o(wo),.window_discontinuity_o(wd),.window_accepted_count_o(waccept),.window_dropped_count_o(wdrop),.aborted_windows_o(aborts),
        .rx_frame_count_o(received),.uart_error_count_o(uart_errors),.checksum_error_count_o(checksum_errors),.timeout_count_o(timeouts),.seq_error_count_o(seq_errors),
        .raw_x_o(),.raw_y_o(),.raw_z_o(),.accepted_count_o(),.dropped_count_o(),.completed_count_o(),.filter_accepted_count_o(),.filter_dropped_count_o(),.filter_restart_count_o());
    wire default_done;wire [31:0] default_errors;
    stage5_default_smoke default_case(clk,default_done,default_errors);
    wire quality_done;wire [31:0] quality_errors;
    stage5_quality_gate quality_case(clk,quality_done,quality_errors);
    `include "stage5_check.vh"
    reg [7:0] expected_bytes[0:32767];
    integer expected_x[0:4095],expected_y[0:4095],expected_z[0:4095],expected_seq[0:4095];
    integer byte_total=0,byte_seen=0,frame_total=0,frame_seen=0,feature_seen=0,raw_cycle=0,cycle=0;
    integer file,fe,fo,status,n=0,a,b,c,ea,eb,ec,j,k,cut,bit_index,ei,es,ee,erx,ery,erz,epx,epy,epz,eaxes,erise,efall;
    reg [34:0] emx,emy,emz;
    reg [7:0] decoded;reg [79:0] truncated_packet;
    function [79:0] packet;
        input [7:0] s;input [15:0] x,y,z;
        begin packet={16'ha55a,s,x,y,z,(s^x[15:8]^x[7:0]^y[15:8]^y[7:0]^z[15:8]^z[7:0])};end
    endfunction
    task expect_frame;
        input integer s,x,y,z,gx,gy,gz;reg [79:0] p;integer i;
        begin
            p=packet(s,x,y,z);
            for(i=0;i<10;i=i+1)begin expected_bytes[byte_total]=p[79:72];byte_total=byte_total+1;p={p[71:0],8'd0};end
            expected_seq[frame_total]=s & 255;expected_x[frame_total]=gx;expected_y[frame_total]=gy;expected_z[frame_total]=gz;frame_total=frame_total+1;
        end
    endtask
    task send_byte;
        input [7:0] value;input bad_stop;integer i;
        begin
            @(negedge clk);rx=0;repeat(10)@(negedge clk);
            for(i=0;i<8;i=i+1)begin rx=value[i];repeat(10)@(negedge clk);end
            rx=!bad_stop;repeat(10)@(negedge clk);rx=1;
        end
    endtask
    task send_packet;
        input integer s,x,y,z,mode;reg [79:0] p;integer i;
        begin
            p=packet(s,x,y,z);if(mode==1)p[0]=!p[0];if(mode==2)p[79:72]=0;
            for(i=0;i<10;i=i+1)begin send_byte(p[79:72],0);p={p[71:0],8'd0};end
        end
    endtask
    initial forever begin
        @(negedge tx);
        if(!rst)begin
            #100;check(tx===0,"回传起始位");
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin #200;decoded[bit_index]=tx;end
            #200;check(tx===1,"回传停止位");check(byte_seen<byte_total,"无额外原始回传");
            if(byte_seen<byte_total)begin
                check(decoded===expected_bytes[byte_seen],"原始十字节逐字节保持");
            end
            byte_seen=byte_seen+1;
        end
    end
    always @(posedge clk)begin
        cycle=cycle+1;#1;
        if(!rst)begin
            if(raw_valid)raw_cycle=cycle;
            if(filtered_valid)begin
                check(frame_seen<frame_total,"无额外滤波样本");
                if(frame_seen<frame_total)begin
                    check(fs===expected_seq[frame_seen][7:0],"滤波SEQ");
                    check(fx===expected_x[frame_seen] && fy===expected_y[frame_seen] && fz===expected_z[frame_seen],"UART至滤波三轴独立期望");
                end
                frame_seen=frame_seen+1;
            end
            if(wo || wd)check(0,"正常UART间隔不得使窗口过载或失序");
            if(fv)begin
                check(cycle-raw_cycle==218,"原始帧至对齐特征218拍");
                check(av && quality,"新特征与报警状态同拍有效");
                if(feature_seen<12)begin
                    status=$fscanf(fe,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",ei,es,ee,emx,emy,emz,erx,ery,erz,epx,epy,epz,eaxes,erise,efall);
                    check(status==15,"完整集成特征期望");
                    check(wid==ei && ss==es && se==ee,"预热63样本后窗口边界及ID");
                    check(mx===emx && my===emy && mz===emz,"集成三轴能量");
                    check(rmsx==erx && rmsy==ery && rmsz==erz && px==epx && py==epy && pz==epz,"集成RMS及峰值");
                    check(axes===eaxes[2:0] && rise===erise[2:0] && fall===efall[2:0],"集成报警置位和解除与Python一致");
                    $fdisplay(fo,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",wid,ss,se,mx,my,mz,rmsx,rmsy,rmsz,px,py,pz,axes,rise,fall);
                end else begin
                    check(mx==0 && my==0 && mz==0 && axes==0 && rise==0 && fall==0,"错误或复位后常数输入恢复零振动");
                end
                feature_seen=feature_seen+1;
            end
        end
    end
    initial begin
        fe=$fopen("feature_link_expected.txt","r");fo=$fopen("feature_link_capture.txt","w");file=$fopen("feature_link_samples.txt","r");
        check(fe!=0 && fo!=0 && file!=0,"集成向量与导出文件");if(!fe || !fo || !file)finish_test;
        repeat(20)@(posedge clk);@(negedge clk);rst=0;repeat(20)@(posedge clk);
        status=$fscanf(file,"%d %d %d %d %d %d\n",a,b,c,ea,eb,ec);
        while(status==6)begin
            expect_frame((251+n)%256,a,b,c,ea,eb,ec);send_packet((251+n)%256,a,b,c,0);repeat(2990)@(posedge clk);n=n+1;
            status=$fscanf(file,"%d %d %d %d %d %d\n",a,b,c,ea,eb,ec);
        end
        $fclose(file);check(n==1600 && frame_seen==1600 && byte_seen==16000 && feature_seen==12,"1600包及12个完整窗口");
        check(av && axes==0 && any_alarm==0 && wdrop==0 && aborts==0,"低振动恢复且无合法负载丢弃");
        repeat(13000)@(posedge clk);#1;check(!quality && !av && axes==0 && fall==0 && aborts==1,"断流取消部分窗并失效，不伪造解除");
        send_packet(83,123,456,-789,1);send_packet(84,123,456,-789,2);
        for(cut=1;cut<=9;cut=cut+1)begin
            truncated_packet=packet(90+cut,17,18,19);
            for(j=0;j<cut;j=j+1)begin send_byte(truncated_packet[79:72],0);truncated_packet={truncated_packet[71:0],8'd0};end
            repeat(2500)@(posedge clk);check(!av && feature_seen==12,"各截断位置不推进窗口");
        end
        send_byte(8'h00,1);repeat(100)@(posedge clk);
        check(checksum_errors>0 && uart_errors>0 && timeouts>=9,"坏校验、停止位及九处截断");
        for(n=0;n<200;n=n+1)begin
            expect_frame(n%256,17,18,19,0,0,0);send_packet(n%256,17,18,19,0);repeat(2990)@(posedge clk);
        end
        check(feature_seen==13 && av && wid==12 && ss==62 && se==189,"错误恢复重新预热并完成新窗，ID不复用");
        // 不等待断流，主动跳SEQ使历史立即失效，恢复需要重新预热。
        expect_frame(220,17,18,19,0,0,0);send_packet(220,17,18,19,0);repeat(2990)@(posedge clk);
        check(!av && !quality && feature_seen==13,"序号跳变立即取消可信状态");
        for(n=1;n<200;n=n+1)begin
            expect_frame((220+n)%256,17,18,19,0,0,0);send_packet((220+n)%256,17,18,19,0);repeat(2990)@(posedge clk);
        end
        check(feature_seen==14 && av && wid==13 && seq_errors>0,"序号错误后恢复");
        @(negedge clk);rst=1;repeat(3)@(posedge clk);#1;check(!av && !fv && waccept==0,"集成复位取消状态");
        @(negedge clk);rst=0;repeat(20)@(posedge clk);
        for(n=0;n<200;n=n+1)begin
            expect_frame(n%256,17,18,19,0,0,0);send_packet(n%256,17,18,19,0);repeat(2990)@(posedge clk);
        end
        check(feature_seen==15 && av && wid==0 && received==200,"全链路复位后重新完成窗口");
        check(frame_seen==frame_total && byte_seen==byte_total,"全部2200个原始包一一回传");
        wait(default_done);check(default_errors==0,"真实50MHz/115200参数UART冒烟");
        wait(quality_done);check(quality_errors==0,"各质量故障及发布边界注入清理恢复");
        $fclose(fe);$fclose(fo);finish_test;
    end
endmodule
`undef TEST_NAME

// 仅定向注入第四阶段接口质量标志，核查门控优先级；不替代滤波器算术测试。
module stage5_quality_gate(input wire clk,output reg done=0,output reg [31:0] errors=0);
    reg rst=1,qfull=1,qsat=0,qover=0,qrestart=0,sv=0;reg [7:0] seq=0;
    wire fv,av;wire [2:0] axes,fall;wire [17:0] rms;wire [31:0] wid;
    feature_monitor_core #(.WINDOW_LOG2(2),.ASSERT_WINDOWS(1),.RELEASE_WINDOWS(1)) dut(
        .clk(clk),.rst(rst),.pl_rx(1'b1),.feature_valid_o(fv),.alarm_valid_o(av),.alarm_axes_o(axes),.alarm_fall_o(fall),.rms_x_o(rms),.window_id_o(wid),
        .pl_tx(),.raw_valid_o(),.filtered_valid_o(),.history_full_o(),.quality_valid_o(),.raw_seq_o(),.filtered_seq_o(),.raw_x_o(),.raw_y_o(),.raw_z_o(),.filtered_x_o(),.filtered_y_o(),.filtered_z_o(),.ms_x_o(),.ms_y_o(),.ms_z_o(),.rms_y_o(),.rms_z_o(),.peak_x_o(),.peak_y_o(),.peak_z_o(),.seq_start_o(),.seq_end_o(),.alarm_rise_o(),.alarm_any_o(),.window_overrun_o(),.window_discontinuity_o(),.window_accepted_count_o(),.window_dropped_count_o(),.aborted_windows_o(),.rx_frame_count_o(),.uart_error_count_o(),.checksum_error_count_o(),.timeout_count_o(),.seq_error_count_o(),.accepted_count_o(),.dropped_count_o(),.completed_count_o(),.filter_accepted_count_o(),.filter_dropped_count_o(),.filter_restart_count_o());
    integer mode,i,j,old_id;
    task sample;
        begin
            @(negedge clk);sv=1;
            @(negedge clk);sv=0;seq=seq+1'b1;
            repeat(30)@(negedge clk);
        end
    endtask
    initial begin
        force dut.history_full_o=qfull;
        force dut.saturated=qsat;force dut.filter_overrun=qover;force dut.restart=qrestart;
        force dut.filtered_valid_o=sv;force dut.filtered_seq_o=seq;
        force dut.filtered_x_o=18'sd4000;force dut.filtered_y_o=-18'sd4000;force dut.filtered_z_o=18'sd0;
        repeat(4)@(posedge clk);@(negedge clk);rst=0;
        for(mode=0;mode<7;mode=mode+1)begin
            for(i=0;i<4;i=i+1)sample;
            if(!av || axes!=3 || rms!=4000)errors=errors+1;
            old_id=wid;
            // 第七种故障恰在窗口已算完、适配层将发布的沿到达。
            if(mode==6)begin
                for(i=0;i<3;i=i+1)sample;
                @(negedge clk);sv=1;
                @(negedge clk);sv=0;seq=seq+1'b1;
                wait(dut.fv);@(negedge clk);qsat=1;
            end else begin
                sample;
                case(mode)
                    0:qfull=0;
                    1:qsat=1;
                    2:qover=1;
                    3:qrestart=1;
                    // 窗口内部过载与不连续事件分别进入报警清理。
                    4:begin @(negedge clk);sv=1;@(negedge clk);sv=1;@(negedge clk);sv=0;seq=seq+8'd2;end
                    5:begin seq=seq+8'd5;sample;end
                endcase
            end
            repeat(3)@(posedge clk);#1;
            if(av || axes!=0 || fall!=0 || fv)errors=errors+1;
            @(negedge clk);sv=0;qfull=1;qsat=0;qover=0;qrestart=0;
            // 窗口不连续以当前样本开始，其他清理均从下一样本重建。
            if(mode==5)begin
                for(i=0;i<3;i=i+1)sample;
            end else for(i=0;i<4;i=i+1)sample;
            if(!av || axes!=3 || rms!=4000 || wid<=old_id)errors=errors+1;
        end
        done=1;
    end
endmodule

// 默认参数通道不加速：检查原始回包、三轴恒定偏置及FF到00回绕。
module stage5_default_smoke(input wire clk,output reg done=0,output reg [31:0] errors=0);
    reg rst=1,rx=1;wire tx,ov;wire [7:0] seq;
    wire signed [17:0] x,y,z;
    wire [31:0] drops;
    feature_monitor_core dut(.clk(clk),.rst(rst),.pl_rx(rx),.pl_tx(tx),.filtered_valid_o(ov),
        .filtered_seq_o(seq),.filtered_x_o(x),.filtered_y_o(y),.filtered_z_o(z),.filter_dropped_count_o(drops),
        .raw_valid_o(),.history_full_o(),.quality_valid_o(),.raw_seq_o(),.raw_x_o(),.raw_y_o(),.raw_z_o(),.feature_valid_o(),.ms_x_o(),.ms_y_o(),.ms_z_o(),.rms_x_o(),.rms_y_o(),.rms_z_o(),.peak_x_o(),.peak_y_o(),.peak_z_o(),.seq_start_o(),.seq_end_o(),.window_id_o(),.alarm_axes_o(),.alarm_rise_o(),.alarm_fall_o(),.alarm_any_o(),.alarm_valid_o(),.window_overrun_o(),.window_discontinuity_o(),.window_accepted_count_o(),.window_dropped_count_o(),.aborted_windows_o(),.rx_frame_count_o(),.uart_error_count_o(),.checksum_error_count_o(),.timeout_count_o(),.seq_error_count_o(),.accepted_count_o(),.dropped_count_o(),.completed_count_o(),.filter_accepted_count_o(),.filter_restart_count_o());
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
