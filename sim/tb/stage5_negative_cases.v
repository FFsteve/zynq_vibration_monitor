`timescale 1ns/1ps
// 每个顶层只实例化一个非法参数，必须在运行前拒绝，不能运行到哨兵。
module stage5_bad_window_low;
    window_features #(.WINDOW_LOG2(-1)) dut();
    initial begin #100;$display("UNEXPECTED_ACCEPT");$finish;end
endmodule
module stage5_bad_window_high;
    window_features #(.WINDOW_LOG2(11)) dut();
    initial begin #100;$display("UNEXPECTED_ACCEPT");$finish;end
endmodule
module stage5_bad_alarm_equal;
    threshold_alarm #(.RMS_ON(1500),.RMS_OFF(1500)) dut();
    initial begin #100;$display("UNEXPECTED_ACCEPT");$finish;end
endmodule
module stage5_bad_alarm_high;
    threshold_alarm #(.RMS_ON(131073)) dut();
    initial begin #100;$display("UNEXPECTED_ACCEPT");$finish;end
endmodule
module stage5_bad_alarm_zero;
    threshold_alarm #(.RMS_ON(0)) dut();
    initial begin #100;$display("UNEXPECTED_ACCEPT");$finish;end
endmodule
module stage5_bad_alarm_negative;
    threshold_alarm #(.RMS_OFF(-1)) dut();
    initial begin #100;$display("UNEXPECTED_ACCEPT");$finish;end
endmodule
module stage5_bad_assert;
    threshold_alarm #(.ASSERT_WINDOWS(0)) dut();
    initial begin #100;$display("UNEXPECTED_ACCEPT");$finish;end
endmodule
module stage5_bad_release;
    threshold_alarm #(.RELEASE_WINDOWS(256)) dut();
    initial begin #100;$display("UNEXPECTED_ACCEPT");$finish;end
endmodule
