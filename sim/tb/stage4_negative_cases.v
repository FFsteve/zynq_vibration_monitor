`timescale 1ns/1ps
// 这两个顶层应由DUT参数检查提前终止，走到哨兵文件就表示拒绝失败。
module tb_stage4_missing_coeff;
    reg clk=0;always #10 clk=~clk;
    wire ready,valid,sat,full;wire signed [17:0] data;
    fir_lp_serial #(.COEFF_FILE("missing_stage4_test_coeff.mem")) dut(
        .clk(clk),.rst(1'b1),.valid_i(1'b0),.restart_i(1'b0),.data_i(17'sd0),
        .ready_o(ready),.data_o(data),.valid_o(valid),.saturated_o(sat),.history_full_o(full));
    integer f;
    initial begin #100;f=$fopen("unexpected_accept.txt","w");$fdisplay(f,"FAIL missing coefficient accepted");$fclose(f);$finish;end
endmodule
module tb_stage4_invalid_gap;
    reg clk=0;always #10 clk=~clk;
    vibration_filter #(.GAP_TIMEOUT_CLKS(193)) dut(.clk(clk),.rst(1'b1),.frame_valid_i(1'b0),
        .seq_i(8'd0),.x_i(16'sd0),.y_i(16'sd0),.z_i(16'sd0));
    integer f;
    initial begin #100;f=$fopen("unexpected_accept.txt","w");$fdisplay(f,"FAIL invalid gap accepted");$fclose(f);$finish;end
endmodule
