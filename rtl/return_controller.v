`timescale 1ns/1ps
`default_nettype none
// 当前发送包与等待队列分离；队列满时丢弃新包，不覆盖已经接纳的样本。
module return_controller #(
    parameter integer ACK_ONLY=0,
    parameter integer QUEUE_DEPTH=4
) (
    input wire clk,rst,
    input wire frame_valid_i,
    input wire [7:0] seq_i,
    input wire [15:0] x_i,y_i,z_i,
    output wire [7:0] tx_data_o,
    output wire tx_valid_o,
    input wire tx_ready_i,tx_done_i,
    output reg overflow_o,
    output reg packet_done_o,
    output reg [31:0] accepted_count_o,dropped_count_o,completed_count_o,
    output wire [31:0] queued_count_o
);
    function integer width_for;
        input integer n;integer v;
        begin v=n-1;width_for=0;while(v>0)begin width_for=width_for+1;v=v>>1;end
            if(width_for<1)width_for=1;end
    endfunction
    function [79:0] encode;
        input [55:0] s;
        reg [7:0] chk;
        begin
            chk=s[55:48]^s[47:40]^s[39:32]^s[31:24]^s[23:16]^s[15:8]^s[7:0];
            encode={16'ha55a,s,chk};
        end
    endfunction
    localparam integer PW=width_for(QUEUE_DEPTH);
    localparam integer CW=width_for(QUEUE_DEPTH+1);
    localparam [1:0] IDLE=0,SEND=1,ARM_DONE=2,WAIT_DONE=3;
    reg [1:0] state;
    reg [55:0] queue[0:QUEUE_DEPTH-1];
    reg [PW-1:0] rd_ptr,wr_ptr;
    reg [CW-1:0] count;
    reg [79:0] active_packet;
    reg [3:0] byte_index;
    wire pop=((state==IDLE)||((state==WAIT_DONE)&&tx_done_i))&&(count!=0);
    wire push=frame_valid_i&&((count<QUEUE_DEPTH)||pop);
    assign queued_count_o=count;
    assign tx_data_o=ACK_ONLY ? 8'h06 : active_packet[79:72];
    assign tx_valid_o=!rst&&(state==SEND);
    // synthesis translate_off
    initial if(QUEUE_DEPTH<1 || (ACK_ONLY!=0 && ACK_ONLY!=1))begin
        $display("ERROR return_controller parameters");$finish;end
    // synthesis translate_on
    always @(posedge clk) begin
        if(rst)begin
            state<=IDLE;rd_ptr<=0;wr_ptr<=0;count<=0;active_packet<=0;byte_index<=0;
            overflow_o<=0;packet_done_o<=0;
            accepted_count_o<=0;dropped_count_o<=0;completed_count_o<=0;
        end else begin
            overflow_o<=0;packet_done_o<=0;
            if(push)begin
                queue[wr_ptr]<={seq_i,x_i,y_i,z_i};
                wr_ptr<=(wr_ptr==QUEUE_DEPTH-1)?0:wr_ptr+1'b1;
                accepted_count_o<=accepted_count_o+1'b1;
            end else if(frame_valid_i)begin
                overflow_o<=1;dropped_count_o<=dropped_count_o+1'b1;
            end
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:count<=count;
            endcase
            if(pop)begin
                active_packet<=encode(queue[rd_ptr]);
                rd_ptr<=(rd_ptr==QUEUE_DEPTH-1)?0:rd_ptr+1'b1;
                byte_index<=0;state<=SEND;
            end else case(state)
                IDLE:state<=IDLE;
                SEND:if(tx_ready_i)begin
                    active_packet<={active_packet[71:0],8'd0};
                    if(ACK_ONLY || byte_index==9)state<=ARM_DONE;
                    else byte_index<=byte_index+1'b1;
                end
                // 连续 TX 握手时，上一字节的 done 可能延后一拍可见，先忽略它。
                ARM_DONE:state<=WAIT_DONE;
                WAIT_DONE:if(tx_done_i)state<=IDLE;
                default:state<=IDLE;
            endcase
            if(state==WAIT_DONE && tx_done_i)begin
                packet_done_o<=1;completed_count_o<=completed_count_o+1'b1;
            end
        end
    end
endmodule
`default_nettype wire
