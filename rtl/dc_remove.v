`timescale 1ns/1ps
`default_nettype none

// 模块职责：在有效样本域估计缓慢变化基线，去掉偏置/重力的直流分量，为振动统计提供交流量。
// 输入signed16，基线为signed32的Q16格式，输出signed17以容纳输入与基线相减的范围。
// 每个新样本先计算error = input - old_baseline，再更新baseline += error / 32。
// 注意：输出用旧基线计算，不是先更新基线后再相减；这会影响独立参考模型的逐样本结果。
// baseline的除32使用算术右移，负值向负无穷截断；输出Q16转整数采用正负对称的四舍五入。
// 首样本或带restart_i的有效样本直接建立新基线、输出0，避免旧姿态污染新数据段。
// restart_i仅随sample_valid_i采样，不是独立清零输入；上层应在接纳新样本时携带重建标志。
// 本模块不替代传感器六面校准，也不是每轴机械地减去1g。

// 有效样本域的一阶基线估计；输入与输出单位均为原始计数。
module dc_remove (
    input wire clk,rst,sample_valid_i,restart_i,
    input wire signed [15:0] data_i,
    output reg signed [16:0] data_o,
    output reg valid_o
);
    reg initialized;
    reg signed [31:0] baseline_q;
    // 先符号扩展再参与减法，额外一位保存正负极值差，避免16位减法先溢出。
    wire signed [32:0] input_q=$signed({data_i[15],data_i,16'd0});
    wire signed [32:0] error_q=input_q-$signed({baseline_q[31],baseline_q});
    wire signed [32:0] next_baseline=$signed({baseline_q[31],baseline_q})+(error_q >>> 5);
    reg signed [33:0] magnitude,rounded;
    // 先扩成34位再取绝对值，连最负数也能表示；加半个Q16单位后恢复符号，负半值远离零。
    always @* begin
        magnitude=$signed({error_q[32],error_q});
        if(error_q<0) magnitude=-magnitude;
        rounded=(magnitude+34'sd32768) >>> 16;
        if(error_q<0) rounded=-rounded;
    end
    always @(posedge clk) begin
        if(rst) begin
            initialized<=0;baseline_q<=0;data_o<=0;valid_o<=0;
        end else begin
            valid_o<=0;
            // 时钟可以连续运行，但基线只随样本推进；空闲的数十万拍不应重复更新同一个样本。
            if(sample_valid_i) begin
                valid_o<=1;
                if(!initialized || restart_i) begin
                    initialized<=1;baseline_q<={data_i,16'd0};data_o<=0;
                end else begin
                    baseline_q<=next_baseline[31:0];data_o<=rounded[16:0];
                end
            end
        end
    end
endmodule
`default_nettype wire
