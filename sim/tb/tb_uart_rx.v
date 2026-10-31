`timescale 1ns/1ps
`default_nettype none

// 可移植的 Verilog 自检平台，不依赖厂商原语或仿真库。
module tb_uart_rx_case #(
    parameter integer CASE_ID = 0,
    parameter integer BAUD = 115_200
) (
    output reg done,
    output integer error_count,
    output integer received_count,
    output integer framing_count
);
    localparam integer CLK_HZ = 50_000_000;
    localparam real CLK_NS = 1.0e9 / CLK_HZ;
    // 串行激励使用准确的波特率周期，不复用被测模块的整数分频结果。
    localparam real BIT_NS = 1.0e9 / BAUD;
    localparam integer BIT_CLKS = (CLK_HZ + BAUD / 2) / BAUD;
    localparam integer HALF_CLKS = BIT_CLKS / 2;

    reg clk;
    reg rst;
    reg rx_i;
    wire [7:0] data_o;
    wire valid_o;
    wire framing_error_o;
    wire busy_o;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .rst(rst), .rx_i(rx_i), .data_o(data_o),
        .valid_o(valid_o), .framing_error_o(framing_error_o), .busy_o(busy_o)
    );

    reg [7:0] expected_data [0:2047];
    integer write_idx;
    integer read_idx;
    integer expected_errors;
    integer cycle_count;
    integer start_cycle;
    integer seed;
    integer random_value;
    integer i;
    integer j;
    reg previous_valid;
    reg previous_error;
    reg [7:0] previous_data;
    real tx_period;

    initial begin
        clk = 1'b0;
        forever #(CLK_NS / 2.0) clk = !clk;
    end

    task fail;
        input [8*160-1:0] message;
        begin
            error_count = error_count + 1;
            $display("FAIL case=%0d time=%0t: %0s", CASE_ID, $time, message);
        end
    endtask

    task enqueue;
        input [7:0] value;
        begin
            if (write_idx >= 2048)
                fail("scoreboard capacity exceeded");
            else begin
                expected_data[write_idx] = value;
                write_idx = write_idx + 1;
            end
        end
    endtask

    // 生成有界且可复现的逐位抖动，幅度以标称发送位宽的百分比表示。
    task bit_delay;
        input real period_ns;
        input real jitter_percent;
        integer noise;
        real duration_ns;
        begin
            noise = $random(seed) % 1001;
            duration_ns = period_ns * (1.0 + jitter_percent * noise / 100000.0);
            #(duration_ns);
        end
    endtask

    task drive_byte;
        input [7:0] value;
        input real period_ns;
        input real jitter_percent;
        input integer bad_stop;
        integer bit_number;
        begin
            rx_i = 1'b0;
            bit_delay(period_ns, jitter_percent);
            if (busy_o !== 1'b1)
                fail("busy not asserted after the start bit");
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                if (busy_o !== 1'b1)
                    fail("busy not asserted during the data bits");
                rx_i = value[bit_number];
                bit_delay(period_ns, jitter_percent);
            end
            rx_i = (bad_stop == 0);
            bit_delay(period_ns, jitter_percent);
        end
    endtask

    task send_good;
        input [7:0] value;
        input real period_ns;
        input real jitter_percent;
        begin
            enqueue(value);
            drive_byte(value, period_ns, jitter_percent, 0);
        end
    endtask

    task checkpoint;
        input [8*80-1:0] label;
        begin
            #(BIT_NS * 2.0);
            if (read_idx != write_idx)
                fail("missing expected byte at checkpoint");
            if (framing_count != expected_errors)
                fail("missing or extra framing-error event at checkpoint");
            $display("CHECK case=%0d %-0s received=%0d framing=%0d errors=%0d",
                     CASE_ID, label, received_count, framing_count, error_count);
        end
    endtask

    task reset_receiver;
        input integer hold_line_low;
        begin
            @(negedge clk);
            rx_i = (hold_line_low == 0);
            rst = 1'b1;
            repeat (5) @(negedge clk);
            rst = 1'b0;
            #(BIT_NS * 2.0);
        end
    endtask

    // 激励端的期望数据不依赖被测模块的数据或状态。
    // 下方额外观察内部信号，只用于核对设计约定的精确周期时序。
    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (rst)
            start_cycle = -1;
        else if ((dut.state == 3'd1) && dut.rx_prev && !dut.rx_sync)
            start_cycle = cycle_count;

        // 等待非阻塞赋值生效后，再检查寄存器输出。
        #0.001;
        if (rst) begin
            if ((data_o !== 8'h00) || (valid_o !== 1'b0) ||
                (framing_error_o !== 1'b0) || (busy_o !== 1'b0))
                fail("reset outputs incorrect");
            previous_data = 8'h00;
        end else begin
            if ((^{data_o, valid_o, framing_error_o, busy_o}) === 1'bx)
                fail("unknown output after reset");
            if (valid_o && framing_error_o)
                fail("valid and framing error overlap");
            if (valid_o && previous_valid)
                fail("valid pulse is longer than one clock");
            if (framing_error_o && previous_error)
                fail("framing error pulse is longer than one clock");

            if (valid_o) begin
                received_count = received_count + 1;
                if (read_idx >= write_idx)
                    fail("unexpected byte (empty scoreboard)");
                else begin
                    if (data_o !== expected_data[read_idx]) begin
                        $display("DATA case=%0d index=%0d expected=%02h actual=%02h",
                                 CASE_ID, read_idx, expected_data[read_idx], data_o);
                        fail("byte value or order mismatch");
                    end
                    read_idx = read_idx + 1;
                end
                if ((start_cycle < 0) ||
                    ((cycle_count - start_cycle) != HALF_CLKS + 9 * BIT_CLKS))
                    fail("valid cycle differs from specified stop-center timing");
                if (busy_o !== 1'b0)
                    fail("busy not cleared on byte completion");
                previous_data = data_o;
            end else if (data_o !== previous_data)
                fail("data changed without valid (or during an invalid frame)");

            if (framing_error_o) begin
                framing_count = framing_count + 1;
                if (framing_count > expected_errors)
                    fail("unexpected framing-error event");
                if ((cycle_count - start_cycle) != HALF_CLKS + 9 * BIT_CLKS)
                    fail("framing-error cycle differs from stop-center timing");
                if (busy_o !== 1'b0)
                    fail("busy not cleared on invalid stop");
            end
        end
        previous_valid = valid_o;
        previous_error = framing_error_o;
    end

    initial begin
        done = 1'b0;
        error_count = 0;
        received_count = 0;
        framing_count = 0;
        expected_errors = 0;
        write_idx = 0;
        read_idx = 0;
        cycle_count = 0;
        start_cycle = -1;
        previous_valid = 1'b0;
        previous_error = 1'b0;
        previous_data = 8'h00;
        seed = 32'h31415926 + CASE_ID;
        rx_i = 1'b1;
        rst = 1'b1;

        reset_receiver(0);
        checkpoint("reset and idle high");

        // 遍历全部字节，按 8N1 连续发送，字节之间不增加空闲时间。
        for (i = 0; i < 256; i = i + 1)
            send_good(i[7:0], BIT_NS, 0.0);
        checkpoint("all 256 bytes back-to-back");

        // 测试随机数据与间隔；各组使用独立、固定的随机种子。
        for (i = 0; i < 128; i = i + 1) begin
            random_value = $random(seed);
            send_good(random_value[7:0], BIT_NS, 0.0);
            random_value = $random(seed) & 32'h7fffffff;
            #(BIT_NS * (random_value % 4));
        end
        checkpoint("seeded random bytes and idle gaps");

        // 以 1 ns 步长扫描起始相位，覆盖一个完整 PL 时钟周期。
        for (i = 0; i < 20; i = i + 1) begin
            @(negedge clk);
            #(i + 0.237);
            send_good(8'h55, BIT_NS, 0.0);
            send_good(8'haa, BIT_NS, 0.0);
        end
        checkpoint("20 asynchronous start phases");

        // 发送端波特率分别偏离标称值 -2%、-1%、+1%、+2%。
        for (j = -2; j <= 2; j = j + 1) begin
            if (j != 0) begin
                tx_period = BIT_NS / (1.0 + j / 100.0);
                for (i = 0; i < 16; i = i + 1) begin
                    send_good(8'h00, tx_period, 1.0);
                    send_good(8'hff, tx_period, 1.0);
                    send_good(8'h55, tx_period, 1.0);
                    send_good(8'haa, tx_period, 1.0);
                end
            end
        end
        checkpoint("baud offsets through +/-2 percent plus 1 percent bit jitter");

        // 核对起始低脉冲宽度：仅检测到下降沿不足以确认起始位。
        rx_i = 1'b0;
        #(CLK_NS);
        rx_i = 1'b1;
        #(BIT_NS * 2.0);
        rx_i = 1'b0;
        #(BIT_NS * 0.25);
        rx_i = 1'b1;
        #(BIT_NS * 2.0);
        rx_i = 1'b0;
        #(HALF_CLKS * CLK_NS - 2.0 * CLK_NS);
        rx_i = 1'b1;
        checkpoint("false starts shorter than half-bit");
        send_good(8'h96, BIT_NS, 0.0);
        checkpoint("recovery after false start");

        // 低电平覆盖起始采样点后一直为高，会呈现为字节 FF。
        // 单点采样接收器不能保证拒绝这种波形，测试应反映该限制。
        enqueue(8'hff);
        rx_i = 1'b0;
        #(HALF_CLKS * CLK_NS + 2.0 * CLK_NS);
        rx_i = 1'b1;
        #(BIT_NS * 10.0);
        checkpoint("start threshold upper side");

        for (i = 0; i < 3; i = i + 1) begin
            expected_errors = expected_errors + 1;
            drive_byte((i == 0) ? 8'h00 : ((i == 1) ? 8'ha5 : 8'hff),
                       BIT_NS, 0.0, 1);
            rx_i = 1'b1;
            #(BIT_NS * 2.0);
            send_good(8'h3c + i, BIT_NS, 0.0);
        end
        checkpoint("invalid stop, data hold, high-level recovery");

        expected_errors = expected_errors + 1;
        rx_i = 1'b0;
        #(BIT_NS * 40.0);
        rx_i = 1'b1;
        #(BIT_NS * 2.0);
        send_good(8'hc3, BIT_NS, 0.0);
        checkpoint("BREAK produces one error, then recovers");

        // 物理输入为低时执行复位，不应产生伪字节。
        reset_receiver(1);
        #(BIT_NS * 12.0);
        rx_i = 1'b1;
        #((BIT_CLKS - 4) * CLK_NS);
        rx_i = 1'b0;
        #(BIT_NS * 12.0);
        checkpoint("short high does not re-arm after reset-low");
        rx_i = 1'b1;
        #(BIT_NS * 2.0);
        send_good(8'h69, BIT_NS, 0.0);
        checkpoint("reset with input low");

        // 分别在起始位、各个数据位及停止位采样前复位，终止当前接收。
        for (i = 0; i <= 9; i = i + 1) begin
            @(negedge clk);
            rx_i = 1'b0;
            #(BIT_NS * (i + 0.25));
            reset_receiver(1);
            #(BIT_NS);
            rx_i = 1'b1;
            #(BIT_NS * 2.0);
            send_good(8'h80 + i, BIT_NS, 0.0);
        end
        checkpoint("reset aborts START, DATA0..7 and STOP");

        // 偏离数据中心的本用例毛刺应被忽略；中心毛刺则会改变字节。
        // 8N1 没有奇偶校验或包校验，因此中心毛刺不一定产生停止位错误。
        for (j = 0; j < 2; j = j + 1) begin
            enqueue((j == 0) ? 8'h00 : 8'h08);
            rx_i = 1'b0;
            #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                rx_i = 1'b0;
                if (i == 3) begin
                    if (j == 0)
                        #(BIT_NS * 0.10);
                    else
                        #(BIT_NS * 0.35);
                    rx_i = 1'b1;
                    #(BIT_NS * 0.30);
                    rx_i = 1'b0;
                    if (j == 0)
                        #(BIT_NS * 0.60);
                    else
                        #(BIT_NS * 0.35);
                end else
                    #(BIT_NS);
            end
            rx_i = 1'b1;
            #(BIT_NS);
        end
        checkpoint("off-center and center data glitches");

        if (write_idx != received_count)
            fail("final received count mismatch");
        done = 1'b1;
        $display("CASE DONE id=%0d baud=%0d divider=%0d bytes=%0d framing=%0d errors=%0d",
                 CASE_ID, BAUD, BIT_CLKS, received_count, framing_count, error_count);
    end
endmodule

module tb_uart_rx;
    wire main_done;
    wire odd_done;
    wire [31:0] main_errors, odd_errors;
    wire [31:0] main_received, odd_received;
    wire [31:0] main_framing, odd_framing;
    reg test_done;
    integer error_count;
    integer result_file;

    tb_uart_rx_case #(.CASE_ID(0), .BAUD(115_200)) main_case (
        .done(main_done), .error_count(main_errors), .received_count(main_received),
        .framing_count(main_framing)
    );
    // 每位 33 拍，用于检查奇数分频和不同的计数器位宽。
    tb_uart_rx_case #(.CASE_ID(1), .BAUD(1_500_000)) odd_case (
        .done(odd_done), .error_count(odd_errors), .received_count(odd_received),
        .framing_count(odd_framing)
    );

    initial begin
        test_done = 1'b0;
        error_count = 0;
        wait (main_done && odd_done);
        #1;
        error_count = main_errors + odd_errors;
        result_file = $fopen("uart_rx_result.txt", "w");
        if (result_file == 0) begin
            error_count = error_count + 1;
            $display("FAIL: cannot write uart_rx_result.txt");
        end
        if (error_count == 0) begin
            $display("PASS tb_uart_rx: bytes=%0d framing=%0d errors=0",
                     main_received + odd_received, main_framing + odd_framing);
            if (result_file != 0)
                $fdisplay(result_file, "PASS bytes=%0d framing=%0d errors=0",
                          main_received + odd_received, main_framing + odd_framing);
        end else begin
            $display("FAIL tb_uart_rx: errors=%0d", error_count);
            if (result_file != 0)
                $fdisplay(result_file, "FAIL errors=%0d", error_count);
        end
        if (result_file != 0)
            $fclose(result_file);
        test_done = 1'b1;
        $finish;
    end

    initial begin
        #100_000_000;
        error_count = 1;
        result_file = $fopen("uart_rx_result.txt", "w");
        if (result_file != 0) begin
            $fdisplay(result_file, "FAIL watchdog timeout");
            $fclose(result_file);
        end
        $display("FAIL tb_uart_rx: 100 ms watchdog timeout");
        $finish;
    end
endmodule

`default_nettype wire
