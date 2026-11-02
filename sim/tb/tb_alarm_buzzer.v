`timescale 1ns/1ps
module tb_alarm_buzzer;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,quality=0,valid=0;
    reg [2:0] axes=0;
    wire beep;
    integer checks=0,errors=0,q,v,a,file_id;
    alarm_buzzer dut(.clk(clk),.rst(rst),.quality_valid_i(quality),.alarm_valid_i(valid),.alarm_axes_i(axes),.beep_o(beep));
    task step;
        input r,qual,val;input [2:0] mask;
        begin
            @(negedge clk);rst=r;quality=qual;valid=val;axes=mask;
            @(posedge clk);#1;checks=checks+1;
            if(beep!==(!r && qual && val && (|mask)))begin errors=errors+1;$display("ERROR buzzer gate");end
        end
    endtask
    initial begin
        step(1,0,0,0);
        // 正常三轴及组合、无报警、质量失效和报警失效的全部输入组合。
        for(q=0;q<2;q=q+1)for(v=0;v<2;v=v+1)for(a=0;a<8;a=a+1)step(0,q,v,a);
        // 报警中失效、恢复、解除及复位优先，随后重新报警。
        step(0,1,1,1);step(0,0,1,1);step(0,1,1,1);step(0,1,0,7);
        step(0,1,1,4);step(0,1,1,0);step(0,1,1,7);step(1,1,1,7);step(0,1,1,2);
        file_id=$fopen("alarm_buzzer_result.txt","w");
        if(errors==0)begin $display("PASS alarm_buzzer checks=%0d errors=0",checks);$fdisplay(file_id,"PASS alarm_buzzer checks=%0d errors=0",checks);end
        else begin $display("FAIL alarm_buzzer checks=%0d errors=%0d",checks,errors);$fdisplay(file_id,"FAIL alarm_buzzer checks=%0d errors=%0d",checks,errors);end
        $fclose(file_id);$finish;
    end
    initial begin #100000;$display("ERROR timeout");$finish;end
endmodule
