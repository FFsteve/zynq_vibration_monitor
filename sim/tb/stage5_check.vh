// 完成标志和当前结果文件共同评分，避免读取历史PASS。
reg test_done=0;
integer error_count=0,checks=0,result_file;
task check;
    input condition;input [959:0] message;
    begin
        checks=checks+1;
        if(condition!==1'b1)begin error_count=error_count+1;if(error_count<21)$display("FAIL %s: %s at %0t",`TEST_NAME,message,$time);end
    end
endtask
task finish_test;
    begin
        result_file=$fopen({`TEST_NAME,"_result.txt"},"w");if(result_file==0)error_count=error_count+1;
        test_done=1;
        if(error_count==0)begin
            $display("PASS %s checks=%0d errors=0",`TEST_NAME,checks);
            if(result_file!=0)$fdisplay(result_file,"PASS %s checks=%0d errors=0",`TEST_NAME,checks);
        end else if(result_file!=0)$fdisplay(result_file,"FAIL %s errors=%0d",`TEST_NAME,error_count);
        if(result_file!=0)$fclose(result_file);$finish;
    end
endtask
initial begin #(64'd5000000000);error_count=error_count+1;$display("FAIL stage5 watchdog");$finish;end
