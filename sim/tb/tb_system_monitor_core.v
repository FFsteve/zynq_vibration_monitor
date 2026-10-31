`timescale 1ns/1ps
`define TEST_NAME "system_monitor_core"
module tb_system_monitor_core;
    wire a,b;wire [31:0] ea,eb,ca,cb;
    stage6_system_case #(.MODE(0)) raw_case(a,ea,ca);
    stage6_system_case #(.MODE(1)) filtered_case(b,eb,cb);
    `include "stage6_check.vh"
    initial begin wait(a && b);checks=ca+cb;check(ea==0 && eb==0,"原始/滤波两模式完整链路");error_count=error_count+ea+eb;finish_test;end
endmodule
`undef TEST_NAME
