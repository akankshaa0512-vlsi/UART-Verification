`timescale 1ns / 1ps

module tb_uart;

    reg        clk;
    reg        rst;
    reg        tx_start;
    reg [7:0]  tx_data;
    wire       tx_out;
    wire [7:0] rx_data;
    wire       rx_done;
    wire       tx_done;
    integer    test_num;
    integer    pass_count;
    integer    fail_count;

    uart_tx DUT_TX (
        .clk      (clk),
        .rst      (rst),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_out   (tx_out),
        .tx_done  (tx_done)
    );

    uart_rx DUT_RX (
        .clk     (clk),
        .rst     (rst),
        .rx_in   (tx_out),
        .rx_data (rx_data),
        .rx_done (rx_done)
    );

    initial clk = 0;
    always #10 clk = ~clk;

    task send_byte;
        input [7:0] data;
        begin
            @(posedge clk);
            tx_data  <= data;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;
            @(posedge rx_done);
            #100;
        end
    endtask

    task check_result;
        input [7:0] expected;
        begin
            test_num = test_num + 1;
            if (rx_data === expected) begin
        $display("TEST%0dPASSED|Sent:0x%0h|Received:0x%0h",
                  test_num, expected, rx_data);
                pass_count = pass_count + 1;
            end
            else begin
       $display("TEST %0d FAILED | Sent:0x%0h | Got:0x%0h",
                test_num, expected, rx_data);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        rst      = 1;
        tx_start = 0;
        tx_data  = 0;
        test_num   = 0;
        pass_count = 0;
        fail_count = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        #100;

      $display("\n Test 1:Sending 0x41 (A)");
      send_byte(8'h41);
      check_result(8'h41);

      $display("\n Test 2:Sending 0x00");
      send_byte(8'h00);
      check_result(8'h00);

      $display("\n Test 3:Sending 0xFF");
      send_byte(8'hFF);
      check_result(8'hFF);

      $display("\n Test 4:Sending 0x55");
      send_byte(8'h55);
      check_result(8'h55);

      $display("\n Test 5:Sending 0xAA");
      send_byte(8'hAA);
      check_result(8'hAA);

      $display("RESULTS: %0d PASSED | %0d FAILED",
               pass_count, fail_count);

        $finish;
    end

endmodule
