`timescale 1ns/1ps
module tb_system_buzzer_top;
    reg clk=0;always #500 clk=~clk;
    reg rx=1;
    wire old_tx,new_tx,beep;
    system_top #(.RETURN_FILTERED(1),.CLK_HZ(1000000),.BAUD(100000),.RESET_HOLD_CLKS(16),.GAP_TIMEOUT_CLKS(12000))
        original(.clk(clk),.pl_rx(rx),.pl_tx(old_tx));
    system_buzzer_top #(.RETURN_FILTERED(1),.CLK_HZ(1000000),.BAUD(100000),.RESET_HOLD_CLKS(16),.GAP_TIMEOUT_CLKS(12000))
        extended(.clk(clk),.pl_rx(rx),.pl_tx(new_tx),.beep(beep));
    integer checks=0,errors=0,n,j,seq=0,alarm_seen=0,release_seen=0,file_id;
    reg old_beep_expected=0;
    reg [79:0] packet;
    integer value;
    task check;
        input condition;
        begin checks=checks+1;if(condition!==1'b1)begin errors=errors+1;if(errors<8)$display("ERROR system buzzer check t=%0t",$time);end end
    endtask
    task byte_send;
        input [7:0] data;integer bit_index;
        begin rx=0;repeat(10)@(negedge clk);
            for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin rx=data[bit_index];repeat(10)@(negedge clk);end
            rx=1;repeat(10)@(negedge clk);
        end
    endtask
    task sample_send;
        input integer x,bad;
        reg [15:0] axis;
        reg [7:0] checksum;
        begin
            axis=x;checksum=seq^axis[15:8]^axis[7:0];
            if(bad)checksum=checksum^8'h01;
            packet={16'ha55a,seq[7:0],axis,32'd0,checksum};
            for(j=0;j<10;j=j+1)begin byte_send(packet[79:72]);packet={packet[71:0],8'd0};end
            seq=(seq+1)%256;repeat(3000)@(negedge clk);
        end
    endtask
    // 每拍核对UART及全部427位调试快照，覆盖蜂鸣器响停期间的原链路等价性。
    always @(posedge clk)begin
        old_beep_expected=!extended.rst && extended.quality_valid_o && extended.alarm_valid_o && (|extended.alarm_axes_o);
        #1;
        check(old_tx===new_tx);
        check({original.debug_feature_valid_o,original.debug_quality_valid_o,original.debug_alarm_valid_o,original.debug_alarm_axes_o,
               original.debug_window_id_o,original.debug_seq_start_o,original.debug_seq_end_o,
               original.debug_ms_x_o,original.debug_ms_y_o,original.debug_ms_z_o,
               original.debug_rms_x_o,original.debug_rms_y_o,original.debug_rms_z_o,
               original.debug_peak_x_o,original.debug_peak_y_o,original.debug_peak_z_o,
               original.debug_rx_frame_count_o,original.debug_dropped_count_o,original.debug_completed_count_o,
               original.debug_filter_restart_count_o,original.debug_aborted_windows_o}
              ===
              {extended.debug_feature_valid_o,extended.debug_quality_valid_o,extended.debug_alarm_valid_o,extended.debug_alarm_axes_o,
               extended.debug_window_id_o,extended.debug_seq_start_o,extended.debug_seq_end_o,
               extended.debug_ms_x_o,extended.debug_ms_y_o,extended.debug_ms_z_o,
               extended.debug_rms_x_o,extended.debug_rms_y_o,extended.debug_rms_z_o,
               extended.debug_peak_x_o,extended.debug_peak_y_o,extended.debug_peak_z_o,
               extended.debug_rx_frame_count_o,extended.debug_dropped_count_o,extended.debug_completed_count_o,
               extended.debug_filter_restart_count_o,extended.debug_aborted_windows_o});
        if($time>20000)check(beep===old_beep_expected);
        if(beep)alarm_seen=1;
        if(alarm_seen && !beep && extended.alarm_valid_o)release_seen=1;
    end
    initial begin
        wait(!extended.rst);repeat(100)@(negedge clk);
        for(n=0;n<96;n=n+1)sample_send(0,0);
        for(n=0;n<384;n=n+1)begin value=$rtoi(12000.0*$sin(6.283185307179586*20.0*n/250.0));sample_send(value,0);end
        check(alarm_seen==1);
        for(n=0;n<384;n=n+1)sample_send(0,0);
        check(release_seen==1 && beep===0);
        // 坏校验不得增加合法接收计数；后续静默触发质量失效，重新输入能正常建窗。
        sample_send(1234,1);check(extended.u_core.checksum_error_count_o==1 && extended.debug_rx_frame_count_o==864);
        repeat(16000)@(negedge clk);check(!extended.quality_valid_o && !beep);
        for(n=0;n<192;n=n+1)sample_send(0,0);
        check(extended.quality_valid_o && extended.alarm_valid_o && !beep);
        check(extended.debug_rx_frame_count_o==1056 && extended.debug_dropped_count_o==0);
        @(negedge clk);
        file_id=$fopen("system_buzzer_top_result.txt","w");
        if(errors==0)begin $display("PASS system_buzzer_top checks=%0d errors=0",checks);$fdisplay(file_id,"PASS system_buzzer_top checks=%0d errors=0",checks);end
        else begin $display("FAIL system_buzzer_top checks=%0d errors=%0d",checks,errors);$fdisplay(file_id,"FAIL system_buzzer_top checks=%0d errors=%0d",checks,errors);end
        $fclose(file_id);$finish;
    end
    initial begin #(64'd5000000000);$display("ERROR system buzzer timeout");$finish;end
endmodule
