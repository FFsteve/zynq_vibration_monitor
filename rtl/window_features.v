`timescale 1ns/1ps
`default_nettype none
// 事件接口：忙时新样本取消整个在途窗口，禁止跨丢样拼接统计。
module window_features #(parameter integer WINDOW_LOG2=7)(
    input wire clk,rst,clear_i,sample_valid_i,
    input wire [7:0] seq_i,
    input wire signed [17:0] x_i,y_i,z_i,
    output wire ready_o,
    output reg feature_valid_o,
    output reg [34:0] ms_x_o,ms_y_o,ms_z_o,
    output reg [17:0] rms_x_o,rms_y_o,rms_z_o,peak_x_o,peak_y_o,peak_z_o,
    output reg [7:0] seq_start_o,seq_end_o,
    output reg [31:0] window_id_o,
    output reg overrun_o,discontinuity_o,
    output reg [31:0] accepted_count_o,dropped_count_o,aborted_windows_o
);
    localparam integer LG=(WINDOW_LOG2<0 || WINDOW_LOG2>10)?7:WINDOW_LOG2;
    localparam integer N=2**LG,SW=36+LG,CW=(LG==0)?1:LG;
    localparam [2:0] IDLE=0,MUL=1,ACC=2,ROOT_START=3,ROOT_WAIT=4;
    reg [2:0] state;
    reg active,have_previous;
    reg [CW-1:0] count;
    reg [7:0] previous_seq,start_seq,sample_seq;
    reg signed [17:0] sx,sy,sz;
    reg [35:0] px,py,pz;
    reg [SW-1:0] sum_x,sum_y,sum_z;
    reg [17:0] peak_x,peak_y,peak_z;
    reg [31:0] next_id;
    reg [34:0] pending_x,pending_y,pending_z;
    reg [17:0] pending_peak_x,pending_peak_y,pending_peak_z;
    wire [SW-1:0] total_x=sum_x+{{LG{1'b0}},px};
    wire [SW-1:0] total_y=sum_y+{{LG{1'b0}},py};
    wire [SW-1:0] total_z=sum_z+{{LG{1'b0}},pz};
    function [17:0] magnitude;
        input signed [17:0] value;
        reg signed [18:0] extended;
        begin extended={value[17],value};magnitude=extended<0 ? -extended : extended;end
    endfunction
    wire [17:0] ax=magnitude(sx),ay=magnitude(sy),az=magnitude(sz);
    wire [17:0] max_x=(ax>peak_x)?ax:peak_x;
    wire [17:0] max_y=(ay>peak_y)?ay:peak_y;
    wire [17:0] max_z=(az>peak_z)?az:peak_z;
    wire broken=have_previous && seq_i!=(previous_seq+8'd1);
    wire overrun=sample_valid_i && state!=IDLE;
    wire root_clear=rst || clear_i || overrun;
    wire root_start=state==ROOT_START;
    wire vx,vy,vz;
    wire [17:0] rx,ry,rz;
    assign ready_o=!rst && !clear_i && state==IDLE;
    isqrt_u36 ux(.clk(clk),.rst(root_clear),.valid_i(root_start),.radicand_i({1'b0,pending_x}),.valid_o(vx),.root_o(rx),
        .ready_o(),.remainder_o());
    isqrt_u36 uy(.clk(clk),.rst(root_clear),.valid_i(root_start),.radicand_i({1'b0,pending_y}),.valid_o(vy),.root_o(ry),
        .ready_o(),.remainder_o());
    isqrt_u36 uz(.clk(clk),.rst(root_clear),.valid_i(root_start),.radicand_i({1'b0,pending_z}),.valid_o(vz),.root_o(rz),
        .ready_o(),.remainder_o());
    // synthesis translate_off
    initial if(WINDOW_LOG2<0 || WINDOW_LOG2>10) begin $display("ERROR stage5 invalid window parameter");$finish;end
    // synthesis translate_on
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;active<=0;have_previous<=0;count<=0;previous_seq<=0;start_seq<=0;sample_seq<=0;
            sx<=0;sy<=0;sz<=0;px<=0;py<=0;pz<=0;sum_x<=0;sum_y<=0;sum_z<=0;
            peak_x<=0;peak_y<=0;peak_z<=0;next_id<=0;pending_x<=0;pending_y<=0;pending_z<=0;
            pending_peak_x<=0;pending_peak_y<=0;pending_peak_z<=0;
            feature_valid_o<=0;ms_x_o<=0;ms_y_o<=0;ms_z_o<=0;rms_x_o<=0;rms_y_o<=0;rms_z_o<=0;
            peak_x_o<=0;peak_y_o<=0;peak_z_o<=0;seq_start_o<=0;seq_end_o<=0;window_id_o<=0;
            overrun_o<=0;discontinuity_o<=0;accepted_count_o<=0;dropped_count_o<=0;aborted_windows_o<=0;
        end else begin
            feature_valid_o<=0;overrun_o<=0;discontinuity_o<=0;
            if(clear_i || overrun) begin
                state<=IDLE;active<=0;have_previous<=0;count<=0;
                sum_x<=0;sum_y<=0;sum_z<=0;peak_x<=0;peak_y<=0;peak_z<=0;
                if(active)aborted_windows_o<=aborted_windows_o+1'b1;
                if(!clear_i && overrun) begin overrun_o<=1;dropped_count_o<=dropped_count_o+1'b1;end
            end else case(state)
                IDLE:if(sample_valid_i) begin
                    sx<=x_i;sy<=y_i;sz<=z_i;sample_seq<=seq_i;previous_seq<=seq_i;have_previous<=1;
                    accepted_count_o<=accepted_count_o+1'b1;active<=1;state<=MUL;
                    if(broken || !active) begin
                        start_seq<=seq_i;count<=0;sum_x<=0;sum_y<=0;sum_z<=0;peak_x<=0;peak_y<=0;peak_z<=0;
                    end
                    if(broken) begin
                        discontinuity_o<=1;
                        if(active)aborted_windows_o<=aborted_windows_o+1'b1;
                    end
                end
                MUL:begin px<=$signed(sx)*$signed(sx);py<=$signed(sy)*$signed(sy);pz<=$signed(sz)*$signed(sz);state<=ACC;end
                ACC:begin
                    if(count==N-1) begin
                        pending_x<=total_x>>LG;pending_y<=total_y>>LG;pending_z<=total_z>>LG;
                        pending_peak_x<=max_x;pending_peak_y<=max_y;pending_peak_z<=max_z;
                        sum_x<=0;sum_y<=0;sum_z<=0;peak_x<=0;peak_y<=0;peak_z<=0;count<=0;state<=ROOT_START;
                    end else begin
                        sum_x<=total_x;sum_y<=total_y;sum_z<=total_z;peak_x<=max_x;peak_y<=max_y;peak_z<=max_z;
                        count<=count+1'b1;state<=IDLE;
                    end
                end
                ROOT_START:state<=ROOT_WAIT;
                ROOT_WAIT:if(vx && vy && vz) begin
                    ms_x_o<=pending_x;ms_y_o<=pending_y;ms_z_o<=pending_z;rms_x_o<=rx;rms_y_o<=ry;rms_z_o<=rz;
                    peak_x_o<=pending_peak_x;peak_y_o<=pending_peak_y;peak_z_o<=pending_peak_z;
                    seq_start_o<=start_seq;seq_end_o<=sample_seq;window_id_o<=next_id;next_id<=next_id+1'b1;
                    feature_valid_o<=1;active<=0;state<=IDLE;
                end
                default:begin state<=IDLE;active<=0;have_previous<=0;end
            endcase
        end
    end
endmodule
`default_nettype wire
