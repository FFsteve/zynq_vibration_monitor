`timescale 1ns/1ps
// 双模式使用相同独立数值期望；仅串口引脚上的独立解码结果参与回包评分。
module stage6_system_case #(parameter integer MODE=0)(output reg done=0,output integer error_count=0,output integer checks=0);
    reg clk=0;always #10 clk=~clk;
    reg rst=1,rx=1,pause=0;
    wire tx,raw_valid,filtered_valid,fv,full,quality,av,ov;
    wire [7:0] fs,ss,se;wire signed [17:0] fx,fy,fz;wire [34:0] mx,my,mz;
    wire [17:0] rmsx,rmsy,rmsz,px,py,pz;wire [2:0] axes;
    wire [31:0] wid,received,accepted,dropped,completed,queued,filter_accepted,filter_dropped,window_accepted,aborts;
    wire [31:0] uart_errors,checksum_errors,timeouts,seq_errors;
    system_monitor_core #(.RETURN_FILTERED(MODE),.CLK_HZ(1152000),.BAUD(115200),.BYTE_TIMEOUT_CLKS(2304),.GAP_TIMEOUT_CLKS(13824)) dut(
        .clk(clk),.rst(rst),.pl_rx(rx),.tx_pause_i(pause),.pl_tx(tx),.raw_valid_o(raw_valid),.filtered_valid_o(filtered_valid),
        .filtered_seq_o(fs),.filtered_x_o(fx),.filtered_y_o(fy),.filtered_z_o(fz),.history_full_o(full),.quality_valid_o(quality),
        .feature_valid_o(fv),.ms_x_o(mx),.ms_y_o(my),.ms_z_o(mz),.rms_x_o(rmsx),.rms_y_o(rmsy),.rms_z_o(rmsz),
        .peak_x_o(px),.peak_y_o(py),.peak_z_o(pz),.seq_start_o(ss),.seq_end_o(se),.window_id_o(wid),.alarm_axes_o(axes),.alarm_valid_o(av),
        .rx_frame_count_o(received),.accepted_count_o(accepted),.dropped_count_o(dropped),.completed_count_o(completed),.queued_count_o(queued),.overflow_o(ov),
        .filter_accepted_count_o(filter_accepted),.filter_dropped_count_o(filter_dropped),.window_accepted_count_o(window_accepted),.aborted_windows_o(aborts),
        .uart_error_count_o(uart_errors),.checksum_error_count_o(checksum_errors),.timeout_count_o(timeouts),.seq_error_count_o(seq_errors),
        .packet_done_o(),.selected_valid_o(),.selected_seq_o(),.selected_x_o(),.selected_y_o(),.selected_z_o(),.raw_seq_o(),.raw_x_o(),.raw_y_o(),.raw_z_o(),.alarm_rise_o(),.alarm_fall_o(),.alarm_any_o(),.window_overrun_o(),.window_discontinuity_o(),.window_dropped_count_o(),.filter_restart_count_o());
    reg [7:0] expected_bytes[0:131071];
    integer expected_x[0:16383],expected_y[0:16383],expected_z[0:16383],expected_seq[0:16383];
    integer byte_total=0,byte_seen=0,frame_total=0,frame_seen=0,feature_seen=0,cycle=0,raw_cycle=0,selected_cycle=0;
    integer epoch=0,start_epoch=0,first_starts=0,stall_features=0,last_raw_case=-1,wire_timing_file;
    integer file,fe,fo,fc,binfile,latfile,status,case_id,previous_case=-1,n=0,a,b,c,ex,ey,ez,s,i,j,cut,bit_index;
    integer ei,es,ee,erx,ery,erz,epx,epy,epz,eaxes;
    integer old_acc,old_drop,old_completed,old_frames,old_features;
    reg [34:0] emx,emy,emz;reg [7:0] decoded;reg [79:0] truncated;
    task check;
        input condition;input [959:0] message;
        begin checks=checks+1;if(condition!==1'b1)begin error_count=error_count+1;if(error_count<21)$display("FAIL system MODE=%0d %s at %0t",MODE,message,$time);end end
    endtask
    function [79:0] packet;
        input [7:0] seq;input [15:0] x,y,z;
        begin packet={16'ha55a,seq,x,y,z,(seq^x[15:8]^x[7:0]^y[15:8]^y[7:0]^z[15:8]^z[7:0])};end
    endfunction
    task expect_frame;
        input integer seq,x,y,z,gx,gy,gz,returned;
        reg [79:0] p;integer k;
        begin
            expected_seq[frame_total]=seq & 255;expected_x[frame_total]=gx;expected_y[frame_total]=gy;expected_z[frame_total]=gz;frame_total=frame_total+1;
            p=MODE ? packet(seq,gx>>>2,gy>>>2,gz>>>2) : packet(seq,x,y,z);
            if(returned)for(k=0;k<10;k=k+1)begin expected_bytes[byte_total]=p[79:72];byte_total=byte_total+1;p={p[71:0],8'd0};end
        end
    endtask
    task send_byte;
        input [7:0] value;input bad_stop;integer k;
        begin
            @(negedge clk);rx=0;repeat(10)@(negedge clk);
            for(k=0;k<8;k=k+1)begin rx=value[k];repeat(10)@(negedge clk);end
            rx=!bad_stop;repeat(10)@(negedge clk);rx=1;
        end
    endtask
    task send_packet;
        input integer seq,x,y,z,mode;reg [79:0] p;integer k;
        begin
            p=packet(seq,x,y,z);if(mode==1)p[0]=!p[0];if(mode==2)p[79:72]=0;
            for(k=0;k<10;k=k+1)begin send_byte(p[79:72],0);p={p[71:0],8'd0};end
        end
    endtask
    task send_constant;
        input integer seq,returned;
        begin expect_frame(seq,17,18,19,0,0,0,returned);send_packet(seq,17,18,19,0);repeat(3599)@(posedge clk);end
    endtask
    task gap;
        begin repeat(14000)@(posedge clk);#1;check(!quality && !av && axes==0,"断流质量和报警失效");end
    endtask
    task reset_all;
        begin
            @(negedge clk);rst=1;rx=1;epoch=epoch+1;byte_seen=byte_total;frame_seen=frame_total;
            repeat(3)@(posedge clk);#1;
            check(received==0 && accepted==0 && dropped==0 && completed==0 && queued==0,"复位清接收和真实输出队列诊断");
            check(filter_accepted==0 && filter_dropped==0 && window_accepted==0 && aborts==0 && !fv && !av && !full,"复位清全部计算支路状态");
            check(tx===1,"复位中TX回到空闲");
            @(negedge clk);rst=0;repeat(30)@(posedge clk);
        end
    endtask
    // 不借用DUT uart_rx或tx_done解码；复位跨字节时取消当前观测。
    initial forever begin
        @(negedge tx);
        if(!rst)begin
            start_epoch=epoch;
            if(frame_total<=5632)$fdisplay(wire_timing_file,"%0d %0d",byte_seen,cycle);
            if(first_starts<5632 && byte_seen%10==0 && frame_total<=5632)begin
                check(cycle-raw_cycle==(MODE?198:4),"空队列原始/滤波首位延迟");
                $fdisplay(latfile,"%0d %0d",first_starts,cycle-raw_cycle);
                first_starts=first_starts+1;
            end
            // 每个包只在第一字节比较延迟，字节边沿由已解码数量确定。
            #100;
            if(start_epoch==epoch && !rst)check(tx===0,"回包起始位中心");
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin #200;decoded[bit_index]=tx;end
            #200;
            if(start_epoch==epoch && !rst)begin
                check(tx===1,"回包停止位中心");check(byte_seen<byte_total,"没有多余回包字节");
                if(byte_seen<byte_total)check(decoded===expected_bytes[byte_seen],"逐字节独立回包期望");
                if(frame_total<=5632)$fwrite(binfile,"%c",decoded);
                byte_seen=byte_seen+1;
            end
        end
    end
    always @(posedge clk)begin
        cycle=cycle+1;#1;
        if(!rst)begin
            if(raw_valid)begin
                if(frame_total<=5632 && last_raw_case==case_id)check(cycle-raw_cycle==4608,"长序列严格4608拍即名义250包/s");
                last_raw_case=case_id;raw_cycle=cycle;
            end
            if(filtered_valid)begin
                check(frame_seen<frame_total,"无额外滤波事件");
                if(frame_seen<frame_total)begin
                    check(fs===expected_seq[frame_seen][7:0],"滤波SEQ和跨包快照");
                    check(fx===expected_x[frame_seen] && fy===expected_y[frame_seen] && fz===expected_z[frame_seen],"全部三轴与独立定点参考相同");
                end
                if(frame_seen<5632)$fdisplay(fc,"%0d %0d %0d %0d",fs,fx,fy,fz);
                frame_seen=frame_seen+1;
            end
            if(fv)begin
                check(cycle-raw_cycle==218 && av && quality,"特征218拍及报警同拍有效");
                if(pause)stall_features=stall_features+1;
                if(feature_seen<40)begin
                    status=$fscanf(fe,"%d %d %d %d %d %d %d %d %d %d %d %d %d\n",ei,es,ee,emx,emy,emz,erx,ery,erz,epx,epy,epz,eaxes);
                    check(status==13 && wid==ei && ss==es && se==ee,"完整窗口ID和边界");
                    check(mx===emx && my===emy && mz===emz && rmsx==erx && rmsy==ery && rmsz==erz,"三轴能量和RMS");
                    check(px==epx && py==epy && pz==epz && axes===eaxes[2:0],"三轴峰值和报警隔离");
                    $fdisplay(fo,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",wid,ss,se,mx,my,mz,rmsx,rmsy,rmsz,px,py,pz,axes);
                end else check(mx==0 && my==0 && mz==0 && axes==0,"恢复常数输入无旧振动历史");
                feature_seen=feature_seen+1;
            end
        end
    end
    initial begin
        file=$fopen("system_vectors.txt","r");fe=$fopen("system_features.txt","r");
        if(MODE)begin fo=$fopen("features_filtered.txt","w");fc=$fopen("internal_filtered.txt","w");binfile=$fopen("wire_filtered.bin","wb");latfile=$fopen("latency_filtered.txt","w");wire_timing_file=$fopen("wire_timing_filtered.txt","w");end
        else begin fo=$fopen("features_raw.txt","w");fc=$fopen("internal_raw.txt","w");binfile=$fopen("wire_raw.bin","wb");latfile=$fopen("latency_raw.txt","w");wire_timing_file=$fopen("wire_timing_raw.txt","w");end
        check(file!=0 && fe!=0 && fo!=0 && fc!=0 && binfile!=0 && latfile!=0 && wire_timing_file!=0,"系统向量和导出文件");
        repeat(20)@(posedge clk);@(negedge clk);rst=0;repeat(30)@(posedge clk);
        status=$fscanf(file,"%d %d %d %d %d %d %d %d\n",case_id,s,a,b,c,ex,ey,ez);
        while(status==8)begin
            if(case_id!=previous_case && previous_case!=-1)gap;
            previous_case=case_id;
            expect_frame(s,a,b,c,ex,ey,ez,1);send_packet(s,a,b,c,0);repeat(3599)@(posedge clk);n=n+1;
            status=$fscanf(file,"%d %d %d %d %d %d %d %d\n",case_id,s,a,b,c,ex,ey,ez);
        end
        $fclose(file);check(n==5632 && frame_seen==5632 && byte_seen==56320 && feature_seen==40,"长序列和三轴隔离完整数量");
        check(dropped==0 && filter_dropped==0 && completed==5632,"正常250包/s等效负载无丢弃");
        $fclose(fo);$fclose(fc);$fclose(binfile);$fclose(latfile);$fclose(wire_timing_file);gap;
        send_packet(83,123,456,-789,1);send_packet(84,123,456,-789,2);
        for(cut=1;cut<=9;cut=cut+1)begin
            truncated=packet(90+cut,17,18,19);
            for(j=0;j<cut;j=j+1)begin send_byte(truncated[79:72],0);truncated={truncated[71:0],8'd0};end
            repeat(2500)@(posedge clk);check(feature_seen==40 && !av,"九处截断不产生特征");
        end
        send_byte(0,1);repeat(100)@(posedge clk);
        check(checksum_errors>0 && uart_errors>0 && timeouts>=9,"坏帧和超时诊断覆盖");
        for(i=0;i<200;i=i+1)send_constant(i%256,1);
        check(feature_seen==41 && av && ss==62 && se==189,"错误后完整重新预热恢复");
        // 重复和跳号均按当前样本重建，不能延续旧部分窗。
        send_constant(199,1);check(!av,"重复SEQ失效");send_constant(220,1);check(!av,"跳SEQ失效");
        for(i=1;i<200;i=i+1)send_constant((220+i)%256,1);
        check(feature_seen==42 && seq_errors>0 && av,"重复/丢号后恢复");gap;
        old_acc=accepted;old_drop=dropped;old_completed=completed;old_frames=frame_seen;old_features=feature_seen;
        @(negedge clk);pause=1;
        for(i=0;i<256;i=i+1)send_constant(i%256,i<5);
        check(accepted==old_acc+5 && dropped==old_drop+251 && completed==old_completed && queued==4,"暂停期间在途一包加等待四包，满队列只丢新包");
        check(frame_seen==old_frames+256 && filter_dropped==0 && feature_seen==old_features+1 && stall_features>=1,"输出堵塞不反压滤波、窗口和报警");
        @(negedge clk);pause=0;repeat(7000)@(posedge clk);#1;
        check(completed==old_completed+5 && queued==0 && byte_seen==byte_total,"撤暂停按接纳顺序排空");
        reset_all;
        // 当前包、等待队列均未完成时复位，不允许旧包在复位后继续发送。
        @(negedge clk);pause=1;
        for(i=0;i<8;i=i+1)send_constant(i,i<5);
        check(queued==4 && dropped==3,"复位前创建真实积压");reset_all;
        @(negedge clk);pause=0;repeat(1500)@(posedge clk);#1;check(tx===1 && completed==0,"复位丢弃所有旧发送上下文");
        fork
            begin send_constant(0,1);end
            begin @(negedge tx);repeat(3)@(posedge clk);@(negedge clk);pause=1;repeat(150)@(negedge clk);pause=0;end
        join
        repeat(1500)@(posedge clk);#1;check(completed==1 && byte_seen==byte_total,"字节中途请求暂停仍完整发送，后续只握手一次");
        reset_all;
        // 在滤波运算尚未完成时复位，恢复后第一输出和全部窗口应为零。
        fork
            begin expect_frame(77,30000,-30000,12345,0,0,0,0);send_packet(77,30000,-30000,12345,0);end
            begin @(posedge raw_valid);repeat(40)@(posedge clk);reset_all;end
        join
        for(i=0;i<200;i=i+1)send_constant(i%256,1);
        check(av && wid==0 && received==200 && completed==200 && dropped==0 && filter_dropped==0,"全状态复位后的零基线/零历史完整恢复");
        check(byte_seen==byte_total && frame_seen==frame_total,"最终接纳输出守恒");
        $fclose(fe);done=1;
    end
endmodule
