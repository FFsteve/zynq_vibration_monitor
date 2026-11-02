`timescale 1ns/1ps
`default_nettype none

// 模块职责：锁存一包三轴输入，依次启动去直流和三个同步FIR，最后连同原SEQ一起发布。
// 主流程为IDLE、DC、FIR、WAIT_RESULT；XYZ完全并行处理，只有三轴valid一致才提交一组。
// 默认从接纳到filtered_valid_o为193拍；这是数字计算延迟，不是63抽头的31样本群延迟。
// frame_valid_i是不可等待的一拍事件；忙时到达的样本丢弃、计数并要求下次重建，避免静默跨丢样卷积。
// 三类连续性破坏：SEQ不等于前包加1、默认12ms无新包、运算忙时丢样；均清除历史可信状态。
// 断流计数用clk推进，饱和后保持；重建在下一次接纳时同时送给基线和FIR。
// 第一包建立初始历史，但不作为故障重启计数；后续实际不连续才产生stream_restart_o事件。
// 输出数值在无valid时保持；history_full_o还受失效条件门控，不能只看上一轮存下的full_reg。

// 包有效是一拍事件：忙时丢弃并记录，下次接纳时重建基线和历史。
module vibration_filter #(
    parameter integer GAP_TIMEOUT_CLKS=600000,
    parameter COEFF_FILE="fir_lp_63_q16.mem"
) (
    input wire clk,rst,frame_valid_i,
    input wire [7:0] seq_i,
    input wire signed [15:0] x_i,y_i,z_i,
    output wire ready_o,busy_o,
    output reg filtered_valid_o,
    output reg [7:0] seq_o,
    output reg signed [17:0] x_o,y_o,z_o,
    output wire history_full_o,
    output reg saturated_o,overrun_o,stream_restart_o,
    output reg [31:0] accepted_count_o,dropped_count_o,restart_count_o
);
    function integer count_width;
        input integer value;integer v;
        begin v=value-1;count_width=0;while(v>0)begin count_width=count_width+1;v=v>>1;end
            if(count_width<1)count_width=1;end
    endfunction
    localparam integer GW=count_width(GAP_TIMEOUT_CLKS+1);
    localparam [GW-1:0] GAP_LAST=GAP_TIMEOUT_CLKS-1;
    localparam [GW-1:0] GAP_LIMIT=GAP_TIMEOUT_CLKS;
    localparam [1:0] IDLE=0,DC=1,FIR=2,WAIT_RESULT=3;
    reg [1:0] state;
    reg have_sample,need_restart,active_restart,full_reg;
    reg [GW-1:0] gap_count;
    reg [7:0] previous_seq,active_seq;
    reg signed [15:0] active_x,active_y,active_z;
    // gap_due包含边界即将到达的一拍，用于禁止边界新包与旧历史拼接；gap_expired用于持续失效门控。
    wire gap_expired=have_sample && gap_count==GAP_LIMIT;
    wire gap_due=have_sample && gap_count>=GAP_LAST;
    wire discontinuity=have_sample && (seq_i!=(previous_seq+8'd1));
    wire accept=frame_valid_i && ready_o;
    // 用组合条件直接参与本拍接纳，不能只依赖同沿才置位的need_restart，否则会晚一个样本。
    wire restart_now=need_restart || gap_due || discontinuity;
    wire dc_valid=(state==DC);
    wire fir_valid=(state==FIR);
    wire signed [16:0] dx,dy,dz;
    wire dvx,dvy,dvz,frx,fry,frz,fvx,fvy,fvz,fsx,fsy,fsz,fhx,fhy,fhz;
    wire signed [17:0] fx,fy,fz;
    assign ready_o=!rst && state==IDLE;
    assign busy_o=!ready_o && !rst;
    assign history_full_o=full_reg && !need_restart && !gap_expired && !rst;
    // 三个轴共享有效和重建条件；去直流先寄存，再由FIR状态在下一拍消费稳定结果。
    dc_remove ux(.clk(clk),.rst(rst),.sample_valid_i(dc_valid),.restart_i(active_restart),.data_i(active_x),.data_o(dx),.valid_o(dvx));
    dc_remove uy(.clk(clk),.rst(rst),.sample_valid_i(dc_valid),.restart_i(active_restart),.data_i(active_y),.data_o(dy),.valid_o(dvy));
    dc_remove uz(.clk(clk),.rst(rst),.sample_valid_i(dc_valid),.restart_i(active_restart),.data_i(active_z),.data_o(dz),.valid_o(dvz));
    fir_lp_serial #(.COEFF_FILE(COEFF_FILE)) fxu(.clk(clk),.rst(rst),.valid_i(fir_valid),.restart_i(active_restart),.data_i(dx),.ready_o(frx),.data_o(fx),.valid_o(fvx),.saturated_o(fsx),.history_full_o(fhx));
    fir_lp_serial #(.COEFF_FILE(COEFF_FILE)) fyu(.clk(clk),.rst(rst),.valid_i(fir_valid),.restart_i(active_restart),.data_i(dy),.ready_o(fry),.data_o(fy),.valid_o(fvy),.saturated_o(fsy),.history_full_o(fhy));
    fir_lp_serial #(.COEFF_FILE(COEFF_FILE)) fzu(.clk(clk),.rst(rst),.valid_i(fir_valid),.restart_i(active_restart),.data_i(dz),.ready_o(frz),.data_o(fz),.valid_o(fvz),.saturated_o(fsz),.history_full_o(fhz));
    // synthesis translate_off
    initial if(GAP_TIMEOUT_CLKS<=193) begin $display("ERROR filter gap must exceed latency");$finish;end
    always @(posedge clk) if(!rst) begin
        if(state==FIR && !(frx && fry && frz && dvx && dvy && dvz)) begin
            $display("ERROR filter pipeline handshake");$finish;
        end
        if((fvx!=fvy)||(fvx!=fvz)) begin $display("ERROR filter axis alignment");$finish;end
    end
    // synthesis translate_on
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;have_sample<=0;need_restart<=0;gap_count<=0;
            active_restart<=0;previous_seq<=0;active_seq<=0;active_x<=0;active_y<=0;active_z<=0;
            filtered_valid_o<=0;seq_o<=0;x_o<=0;y_o<=0;z_o<=0;full_reg<=0;
            saturated_o<=0;overrun_o<=0;stream_restart_o<=0;
            accepted_count_o<=0;dropped_count_o<=0;restart_count_o<=0;
        end else begin
            filtered_valid_o<=0;saturated_o<=0;overrun_o<=0;stream_restart_o<=0;
            if(have_sample && !gap_expired) gap_count<=gap_count+1'b1;
            if(gap_due) need_restart<=1;
            // 过载不覆盖active_x/y/z/seq，保证正在计算的一包不被新包撕裂；下一包从零历史重新开始。
            if(frame_valid_i && !ready_o) begin
                overrun_o<=1;dropped_count_o<=dropped_count_o+1'b1;need_restart<=1;
            end
            case(state)
                IDLE:if(accept) begin
                    active_x<=x_i;active_y<=y_i;active_z<=z_i;active_seq<=seq_i;
                    active_restart<=!have_sample || restart_now;
                    previous_seq<=seq_i;have_sample<=1;gap_count<=0;need_restart<=0;
                    accepted_count_o<=accepted_count_o+1'b1;state<=DC;
                    if(restart_now) begin stream_restart_o<=1;restart_count_o<=restart_count_o+1'b1;end
                    if(!have_sample || restart_now) full_reg<=0;
                end
                DC:state<=FIR;
                FIR:state<=WAIT_RESULT;
                // 只有三轴都完成才锁存结果和active_seq；SEQ应随计算走，不能直接取此时外部的seq_i。
                WAIT_RESULT:if(fvx && fvy && fvz) begin
                    x_o<=fx;y_o<=fy;z_o<=fz;seq_o<=active_seq;
                    filtered_valid_o<=1;saturated_o<=fsx || fsy || fsz;
                    full_reg<=fhx && fhy && fhz;state<=IDLE;
                end
                default:begin state<=IDLE;need_restart<=1;full_reg<=0;end
            endcase
        end
    end
endmodule
`default_nettype wire
