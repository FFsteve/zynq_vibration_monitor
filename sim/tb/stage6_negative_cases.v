`timescale 1ns/1ps
// 非法模式必须在仿真开始时被拒绝。
module stage6_bad_mode_low;
    return_source_select #(.RETURN_FILTERED(-1)) dut();
    initial begin #100;$display("UNEXPECTED_ACCEPT");$finish;end
endmodule
module stage6_bad_mode_high;
    return_source_select #(.RETURN_FILTERED(2)) dut();
    initial begin #100;$display("UNEXPECTED_ACCEPT");$finish;end
endmodule
