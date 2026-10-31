`timescale 1ns/1ps
`define TEST_NAME "window_features"
module tb_window_features;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,clear=0,sv=0;reg [7:0] seq=0;reg signed [17:0] x=0,y=0,z=0;
    wire ready,fv,overrun,disc;wire [34:0] mx,my,mz;
    wire [17:0] rx,ry,rz,px,py,pz;wire [7:0] ss,se;wire [31:0] wid,accepts,drops,aborts;
    window_features dut(.clk(clk),.rst(rst),.clear_i(clear),.sample_valid_i(sv),.seq_i(seq),.x_i(x),.y_i(y),.z_i(z),
        .ready_o(ready),.feature_valid_o(fv),.ms_x_o(mx),.ms_y_o(my),.ms_z_o(mz),.rms_x_o(rx),.rms_y_o(ry),.rms_z_o(rz),
        .peak_x_o(px),.peak_y_o(py),.peak_z_o(pz),.seq_start_o(ss),.seq_end_o(se),.window_id_o(wid),
        .overrun_o(overrun),.discontinuity_o(disc),.accepted_count_o(accepts),.dropped_count_o(drops),.aborted_windows_o(aborts));
    wire [3:0] pdone;wire [31:0] pe0,pe1,pe2,pe3;
    stage5_window_parameter #(.LG(0)) p0(clk,pdone[0],pe0);
    stage5_window_parameter #(.LG(1)) p1(clk,pdone[1],pe1);
    stage5_window_parameter #(.LG(2)) p2(clk,pdone[2],pe2);
    stage5_window_parameter #(.LG(10)) p3(clk,pdone[3],pe3);
    `include "stage5_check.vh"
    integer fi,fe,fo,status,window,n=0,j,a,b,c,ei,es,ee,erx,ery,erz,epx,epy,epz,k,delay_cycles;
    reg [34:0] ex,ey,ez;
    reg [31:0] before_abort,before_drop;
    task pulse;
        input integer s,xx,yy,zz;
        begin
            @(negedge clk);check(ready,"样本接纳ready");seq=s;x=xx;y=yy;z=zz;sv=1;
            @(posedge clk);#1;check(!ready && !fv,"锁存沿进入忙");
            @(negedge clk);sv=0;
        end
    endtask
    task finish_sample;
        input last;
        begin
            for(j=1;j<=(last?22:2);j=j+1)begin
                @(posedge clk);#1;
                if(last && j==22)check(fv && ready,"末样本后第22拍发布");
                else check(!fv,"非发布拍没有结果");
            end
            if(!last)check(ready,"普通样本第2拍完成");
        end
    endtask
    task clean;
        begin @(negedge clk);clear=1;sv=1;@(posedge clk);#1;check(!fv && !overrun && !ready,"清理优先于输入");
            @(negedge clk);clear=0;sv=0;end
    endtask
    task constant_window;
        input integer start;
        begin
            for(k=0;k<128;k=k+1)begin pulse((start+k)%256,-131072,4321,-17);finish_sample(k==127);end
            check(mx==35'd17179869184 && my==35'd18671041 && mz==289,"恢复后的能量无旧数据");
            check(rx==131072 && ry==4321 && rz==17 && px==131072,"最负数和峰值不溢出");
            check(ss==start && se==((start+127)%256),"恢复窗口首末序号");
        end
    endtask
    initial begin
        repeat(3)@(posedge clk);@(negedge clk);rst=0;
        fi=$fopen("window_samples.txt","r");fe=$fopen("window_expected.txt","r");fo=$fopen("window_capture.txt","w");
        check(fi!=0 && fe!=0 && fo!=0,"窗口向量及导出文件");if(!fi || !fe || !fo)finish_test;
        for(window=0;window<109;window=window+1)begin
            status=$fscanf(fe,"%d %d %d %d %d %d %d %d %d %d %d %d\n",ei,es,ee,ex,ey,ez,erx,ery,erz,epx,epy,epz);
            check(status==12,"完整窗口期望");
            for(k=0;k<128;k=k+1)begin
                status=$fscanf(fi,"%d %d %d\n",a,b,c);check(status==3,"完整样本输入");
                pulse((250+n)%256,a,b,c);n=n+1;finish_sample(k==127);
            end
            check(wid==ei && ss==es && se==ee,"窗口ID及SEQ回绕");
            check(mx===ex && my===ey && mz===ez,"三轴完整精度均方值");
            check(rx==erx && ry==ery && rz==erz && px==epx && py==epy && pz==epz,"三轴RMS及峰值");
            $fdisplay(fo,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",wid,ss,se,mx,my,mz,rx,ry,rz,px,py,pz);
        end
        $fclose(fi);$fclose(fe);$fclose(fo);check(accepts==13952 && drops==0 && aborts==0,"正常计数和跨窗口连续性");
        // 清理覆盖锁存、乘法、累加、提交开方、开方中及结果同拍。
        for(delay_cycles=0;delay_cycles<22;delay_cycles=delay_cycles+1)begin
            clean;before_abort=aborts;
            for(k=0;k<127;k=k+1)begin pulse(k,1,2,3);finish_sample(0);end
            pulse(127,1,2,3);
            repeat(delay_cycles)@(negedge clk);
            clear=1;@(posedge clk);#1;check(!fv && aborts==before_abort+1,"任意阶段清理取消一个在途窗口");
            repeat(3)begin @(posedge clk);#1;check(aborts==before_abort+1 && !fv,"保持清理不重复计数");end
            @(negedge clk);clear=0;
            repeat(25)begin @(posedge clk);#1;check(!fv,"清理后无迟到结果");end
        end
        // 在各忙阶段施加新事件，优先丢弃而不是提交不完整结果。
        for(delay_cycles=0;delay_cycles<22;delay_cycles=delay_cycles+1)begin
            clean;before_abort=aborts;before_drop=drops;
            for(k=0;k<127;k=k+1)begin pulse(k,1,2,3);finish_sample(0);end
            pulse(127,1,2,3);repeat(delay_cycles)@(negedge clk);
            sv=1;@(posedge clk);#1;
            check(overrun && !fv && drops==before_drop+1 && aborts==before_abort+1,"忙时事件中止且计数一次");
            @(negedge clk);sv=0;repeat(25)begin @(posedge clk);#1;check(!fv,"过载后无旧结果");end
        end
        clean;pulse(254,1,1,1);finish_sample(0);pulse(255,1,1,1);finish_sample(0);pulse(0,1,1,1);finish_sample(0);
        check(!disc,"FF到00不误报");before_abort=aborts;
        pulse(8,1,1,1);check(disc && aborts==before_abort+1,"跳号废弃旧窗");finish_sample(0);
        pulse(8,1,1,1);check(disc && aborts==before_abort+2,"重复序号废弃旧窗");finish_sample(0);
        clean;constant_window(250);check(wid==109,"清理不重置累计窗口ID");
        for(delay_cycles=0;delay_cycles<22;delay_cycles=delay_cycles+1)begin
            @(negedge clk);rst=1;@(negedge clk);rst=0;
            for(k=0;k<127;k=k+1)begin pulse(k,1,2,3);finish_sample(0);end
            pulse(127,1,2,3);repeat(delay_cycles)@(negedge clk);rst=1;
            @(posedge clk);#1;check(!fv && accepts==0 && aborts==0,"各在途阶段全局复位优先");
            @(negedge clk);rst=0;
            repeat(25)begin @(posedge clk);#1;check(!fv,"全局复位后无旧结果");end
        end
        @(negedge clk);rst=1;@(posedge clk);#1;check(accepts==0 && drops==0 && aborts==0 && !fv,"全局复位清诊断");
        @(negedge clk);rst=0;constant_window(0);check(wid==0,"全局复位重置窗口ID");
        wait(&pdone);check(pe0==0 && pe1==0 && pe2==0 && pe3==0,"N为1、2、4、1024边界及复位恢复");finish_test;
    end
endmodule

// 并行覆盖窗口参数边界，输入使用独立解析可得的常数。
module stage5_window_parameter #(parameter integer LG=0)(input wire clk,output reg done=0,output reg [31:0] errors=0);
    reg rst=1,clear=0,sv=0;reg [7:0] seq=0;
    wire ready,fv;wire [34:0] ms;wire [17:0] rms,peak;wire [31:0] wid;
    window_features #(.WINDOW_LOG2(LG)) dut(.clk(clk),.rst(rst),.clear_i(clear),.sample_valid_i(sv),.seq_i(seq),
        .x_i(-18'sd131072),.y_i(18'sd4321),.z_i(-18'sd17),.ready_o(ready),.feature_valid_o(fv),.ms_x_o(ms),.rms_x_o(rms),.peak_x_o(peak),.window_id_o(wid),
        .ms_y_o(),.ms_z_o(),.rms_y_o(),.rms_z_o(),.peak_y_o(),.peak_z_o(),.seq_start_o(),.seq_end_o(),.overrun_o(),.discontinuity_o(),.accepted_count_o(),.dropped_count_o(),.aborted_windows_o());
    integer i,j,w;
    initial begin
        repeat(4)@(posedge clk);@(negedge clk);rst=0;
        for(w=0;w<3;w=w+1)begin
            if(w==2)begin @(negedge clk);rst=1;@(negedge clk);rst=0;end
            for(i=0;i<2**LG;i=i+1)begin
                @(negedge clk);if(!ready)errors=errors+1;sv=1;seq=(w*(2**LG)+i)%256;
                @(negedge clk);sv=0;
                for(j=1;j<=((i==(2**LG)-1)?22:2);j=j+1)begin @(posedge clk);#1;
                    if(fv!==((i==(2**LG)-1)&&(j==22)))errors=errors+1;
                end
            end
            if(ms!==35'd17179869184 || rms!==18'd131072 || peak!==18'd131072 || wid!==((w==2)?0:w))errors=errors+1;
        end
        done=1;
    end
endmodule
`undef TEST_NAME
