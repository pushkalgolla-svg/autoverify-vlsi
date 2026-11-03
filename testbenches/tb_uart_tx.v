`timescale 1ns / 1ps

module tb_uart_tx;

    // Parameters
    parameter CLKS_PER_BIT = 10;
    parameter CLK_PERIOD   = 10; // 10ns period -> 100MHz

    // DUT Signals
    reg        clk;
    reg        rst_n;
    reg        tx_start;
    reg [7:0]  din;
    reg [1:0]  parity_mode;
    wire       tx;
    wire       tx_busy;
    wire       tx_done;

    // Testbench Control Variables
    integer error_count;
    integer i;
    integer j;
    reg [7:0] test_data;
    reg [1:0] test_parity;
    
    // Captured UART frame variables for checking
    reg [7:0] rx_shift_reg;
    reg       rx_parity_calc;
    reg       rx_parity_bit;
    integer   bit_cnt;

    // Instantiate the DUT
    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .din(din),
        .parity_mode(parity_mode),
        .tx(tx),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    // Clock Generator
    always begin
        #(CLK_PERIOD / 2);
        clk = ~clk;
    end

    // Watchdog Timer
    initial begin
        #2000000;
        $display("[ERROR] Watchdog timeout: simulation hung!");
        $finish;
    end

    // VCD Waveform Dumping
    initial begin
        $dumpfile("uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

    // Task to verify a complete UART transmission
    // This task samples the 'tx' line according to CLKS_PER_BIT
    task check_uart_tx;
        input [7:0] expected_data;
        input [1:0] p_mode;
        output integer success;
        
        integer bit_idx;
        integer expected_bits_to_sample;
        reg calc_parity;
        begin
            success = 1;

            // Wait for tx_busy to assert
            @(posedge tx_busy);

            // Wait for start bit (HIGH to LOW transition)
            @(negedge tx);

            // Align to middle of start bit
            #(CLKS_PER_BIT * CLK_PERIOD / 2);
            if (tx !== 1'b0) begin
                $display("[FAIL] Start bit check failed. Expected: 0, Got: %b", tx);
                success = 0;
            end

            // Sample 8 data bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                #(CLKS_PER_BIT * CLK_PERIOD);
                if (tx !== expected_data[bit_idx]) begin
                    $display("[FAIL] Data bit %0d check failed. Expected: %b, Got: %b", bit_idx, expected_data[bit_idx], tx);
                    success = 0;
                end
            end

            // Sample Parity bit if enabled
            if (p_mode != 2'b00) begin
                #(CLKS_PER_BIT * CLK_PERIOD);
                if (p_mode == 2'b01) begin
                    calc_parity = ~(^expected_data);
                end
                else begin
                    calc_parity = ^expected_data;
                end

                if (tx !== calc_parity) begin
                    $display("[FAIL] Parity bit check failed. Mode: %b, Expected: %b, Got: %b", p_mode, calc_parity, tx);
                    success = 0;
                end
            end

            // Sample Stop bit
            #(CLKS_PER_BIT * CLK_PERIOD);
            if (tx !== 1'b1) begin
                $display("[FAIL] Stop bit check failed. Expected: 1, Got: %b", tx);
                success = 0;
            end
        end
    endtask

    // Main Test Sequence
    initial begin
        // Initialize signals
        clk         = 0;
        rst_n       = 0;
        tx_start    = 0;
        din         = 8'h00;
        parity_mode = 2'b00;
        error_count = 0;

        $display("========================================");
        $display("Starting UART Transmitter Testbench");
        $display("========================================");

        // Apply Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        // Test 1: Reset State Verification
        if (tx !== 1'b1) begin
            $display("[FAIL] Reset check: tx should be HIGH, Got: %b", tx);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] Reset check: tx is HIGH");
        end

        if (tx_busy !== 1'b0) begin
            $display("[FAIL] Reset check: tx_busy should be 0, Got: %b", tx_busy);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] Reset check: tx_busy is 0");
        end

        if (tx_done !== 1'b0) begin
            $display("[FAIL] Reset check: tx_done should be 0, Got: %b", tx_done);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] Reset check: tx_done is 0");
        end

        // Test 2: Directed Test - No Parity (2'b00), Data = 8'hA5
        $display("\n--- Test 2: No Parity, Data = 8'hA5 ---");
        @(posedge clk);
        din         = 8'hA5;
        parity_mode = 2'b00;
        tx_start    = 1;
        @(posedge clk);
        tx_start    = 0;

        check_uart_tx(8'hA5, 2'b00, i);
        if (i == 0) begin
            error_count = error_count + 1;
        end else begin
            $display("[PASS] Test 2 Completed Successfully");
        end
        @(posedge tx_done);

        // Test 3: Directed Test - Odd Parity (2'b01), Data = 8'h3C
        $display("\n--- Test 3: Odd Parity, Data = 8'h3C ---");
        #(CLK_PERIOD * 5);
        @(posedge clk);
        din         = 8'h3C;
        parity_mode = 2'b01;
        tx_start    = 1;
        @(posedge clk);
        tx_start    = 0;

        check_uart_tx(8'h3C, 2'b01, i);
        if (i == 0) begin
            error_count = error_count + 1;
        end else begin
            $display("[PASS] Test 3 Completed Successfully");
        end
        @(posedge tx_done);

        // Test 4: Directed Test - Even Parity (2'b10), Data = 8'hF0
        $display("\n--- Test 4: Even Parity, Data = 8'hF0 ---");
        #(CLK_PERIOD * 5);
        @(posedge clk);
        din         = 8'hF0;
        parity_mode = 2'b10;
        tx_start    = 1;
        @(posedge clk);
        tx_start    = 0;

        check_uart_tx(8'hF0, 2'b10, i);
        if (i == 0) begin
            error_count = error_count + 1;
        end else begin
            $display("[PASS] Test 4 Completed Successfully");
        end
        @(posedge tx_done);

        // Test 5: Constrained-Random Stress Testing
        $display("\n--- Test 5: Constrained-Random Stress Testing (10 transactions) ---");
        for (j = 0; j < 10; j = j + 1) begin
            #(CLK_PERIOD * 5);
            test_data   = $random & 8'hFF;
            test_parity = $random & 2'b11;

            @(posedge clk);
            din         = test_data;
            parity_mode = test_parity;
            tx_start    = 1;
            @(posedge clk);
            tx_start    = 0;

            $display("[INFO] Stress test iteration %0d: Data = 0x%0h, Parity Mode = %b", j, test_data, test_parity);
            check_uart_tx(test_data, test_parity, i);
            if (i == 0) begin
                error_count = error_count + 1;
            end
            @(posedge tx_done);
        end
        $display("[PASS] Stress Testing Completed");

        // Test 6: Edge Case - Back-to-Back Transmissions
        $display("\n--- Test 6: Back-to-Back Transmissions ---");
        #(CLK_PERIOD * 5);
        @(posedge clk);
        din         = 8'h55;
        parity_mode = 2'b00;
        tx_start    = 1;
        @(posedge clk);
        tx_start    = 0;

        // Wait for first transmission to finish
        @(posedge tx_done);

        // Immediately start second transmission without idle delay
        @(posedge clk);
        din         = 8'hAA;
        parity_mode = 2'b00;
        tx_start    = 1;
        @(posedge clk);
        tx_start    = 0;

        check_uart_tx(8'hAA, 2'b00, i);
        if (i == 0) begin
            $display("[FAIL] Back-to-back transmission failed");
            error_count = error_count + 1;
        end else begin
            $display("[PASS] Back-to-back transmission passed");
        end
        @(posedge tx_done);

        // Final Results Summary
        $display("\n========================================");
        if (error_count == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d", error_count);
        end
        $display("========================================");

        $finish;
    end

endmodule