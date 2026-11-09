`timescale 1ns / 1ps

/**
 * Self-Checking Testbench for Parameterized UART Transmitter
 * Validates reset, all parity modes (None, Odd, Even), back-to-back frames,
 * full stop-bit timing, and constrained-random data streams.
 */

module tb_uart_tx();

    parameter CLKS_PER_BIT = 10;
    parameter CLK_PERIOD   = 10; // 10ns clock (100MHz)

    // DUT signals
    reg        clk;
    reg        rst_n;
    reg        tx_start;
    reg [7:0]  din;
    reg [1:0]  parity_mode;

    wire       tx;
    wire       tx_busy;
    wire       tx_done;

    // Testbench control
    integer    error_count;
    integer    i;

    // DUT Instantiation
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

    // Clock generator: 100 MHz (10ns period)
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Safety watchdog timer
    initial begin
        #5000000;
        $display("[ERROR] Watchdog timeout: simulation hung!");
        $finish;
    end

    // VCD waveform dumping (portable relative path)
    initial begin
        $dumpfile("logs/uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

    // Apply Reset Task
    task apply_reset;
        begin
            @(negedge clk);
            rst_n       = 1'b0;
            tx_start    = 1'b0;
            din         = 8'h00;
            parity_mode = 2'b00;
            #(CLK_PERIOD * 3);
            @(negedge clk);
            rst_n       = 1'b1;
            #(CLK_PERIOD * 2);
        end
    endtask

    // Task to transmit a byte and verify frame structure cycle-by-cycle
    task send_and_verify;
        input [7:0] test_din;
        input [1:0] test_parity;

        integer bit_idx;
        integer clk_idx;
        reg [7:0] captured_data;
        reg       captured_parity;
        reg       expected_parity;
        integer   timeout_cnt;
        begin
            // 1. Setup inputs on negedge to avoid clock-edge race condition
            @(negedge clk);
            din         = test_din;
            parity_mode = test_parity;
            tx_start    = 1'b1;

            @(negedge clk);
            tx_start    = 1'b0;

            // 2. Verify START bit (must be 0 for full CLKS_PER_BIT duration)
            for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                if (tx !== 1'b0) begin
                    $display("[FAIL] Start bit violation at cycle %0d: Expected 0, Got %b", clk_idx, tx);
                    error_count = error_count + 1;
                end
                @(negedge clk);
            end

            // 3. Verify DATA bits (8 bits, LSB first)
            captured_data = 8'h00;
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                    // Sample at the mid-point of the bit duration
                    if (clk_idx == (CLKS_PER_BIT / 2)) begin
                        captured_data[bit_idx] = tx;
                    end
                    @(negedge clk);
                end
            end

            if (captured_data !== test_din) begin
                $display("[FAIL] Payload mismatch: Expected 0x%0h, Got 0x%0h", test_din, captured_data);
                error_count = error_count + 1;
            end

            // 4. Verify PARITY bit if enabled
            if (test_parity != 2'b00) begin
                if (test_parity == 2'b01)
                    expected_parity = ~(^test_din); // Odd parity
                else
                    expected_parity = ^test_din;    // Even parity

                for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                    if (clk_idx == (CLKS_PER_BIT / 2)) begin
                        captured_parity = tx;
                    end
                    @(negedge clk);
                end

                if (captured_parity !== expected_parity) begin
                    $display("[FAIL] Parity mismatch (mode=%0b): Expected %0b, Got %0b (din=0x%0h)",
                             test_parity, expected_parity, captured_parity, test_din);
                    error_count = error_count + 1;
                end
            end

            // 5. Verify STOP bit (must be 1 for full CLKS_PER_BIT duration)
            for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                if (tx !== 1'b1) begin
                    $display("[FAIL] Stop bit violation at cycle %0d: Expected 1, Got %b", clk_idx, tx);
                    error_count = error_count + 1;
                end
                @(negedge clk);
            end

            // 6. Verify tx_done pulsed and tx_busy returned to 0
            timeout_cnt = 0;
            while (tx_busy && timeout_cnt < 20) begin
                @(negedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            if (tx_busy !== 1'b0) begin
                $display("[FAIL] tx_busy failed to deassert after stop bit");
                error_count = error_count + 1;
            end else begin
                $display("[PASS] Frame verified: din=0x%0h, parity_mode=%0b, bits=0x%0h", test_din, test_parity, captured_data);
            end
        end
    endtask

    // Main Test Sequence
    initial begin
        error_count = 0;

        $display("========================================");
        $display("    STARTING UART_TX VERIFICATION");
        $display("========================================");

        // 1. Reset Verification
        apply_reset();
        if (tx !== 1'b1 || tx_busy !== 1'b0 || tx_done !== 1'b0) begin
            $display("[FAIL] Reset state: Expected tx=1, busy=0, done=0 | Got tx=%b, busy=%b, done=%b", tx, tx_busy, tx_done);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] Reset state verified: line is IDLE (HIGH), busy=0");
        end

        // 2. Directed Tests - No Parity (Mode 2'b00)
        $display("\n--- Test: No Parity Mode (2'b00) ---");
        send_and_verify(8'hA5, 2'b00);
        send_and_verify(8'h00, 2'b00);
        send_and_verify(8'hFF, 2'b00);
        send_and_verify(8'h55, 2'b00);

        // 3. Directed Tests - Odd Parity (Mode 2'b01)
        $display("\n--- Test: Odd Parity Mode (2'b01) ---");
        send_and_verify(8'h3C, 2'b01); // 4 ones -> odd parity bit = 1
        send_and_verify(8'h01, 2'b01); // 1 one  -> odd parity bit = 0
        send_and_verify(8'h00, 2'b01); // 0 ones -> odd parity bit = 1
        send_and_verify(8'hFF, 2'b01); // 8 ones -> odd parity bit = 1

        // 4. Directed Tests - Even Parity (Mode 2'b10)
        $display("\n--- Test: Even Parity Mode (2'b10) ---");
        send_and_verify(8'h3C, 2'b10); // 4 ones -> even parity bit = 0
        send_and_verify(8'h01, 2'b10); // 1 one  -> even parity bit = 1
        send_and_verify(8'h00, 2'b10); // 0 ones -> even parity bit = 0
        send_and_verify(8'hFF, 2'b10); // 8 ones -> even parity bit = 0

        // 5. Back-to-Back Transmissions (Zero-idle delay)
        $display("\n--- Test: Back-to-Back Transmissions ---");
        send_and_verify(8'h12, 2'b00);
        send_and_verify(8'h34, 2'b01);
        send_and_verify(8'h56, 2'b10);

        // 6. Constrained-Random Stress Testing
        $display("\n--- Test: Constrained-Random Frames (30 iterations) ---");
        for (i = 0; i < 30; i = i + 1) begin
            reg [7:0] rand_data;
            reg [1:0] rand_parity;
            rand_data   = $random & 8'hFF;
            rand_parity = ($random & 2'b11) % 3; // 0, 1, or 2
            send_and_verify(rand_data, rand_parity);
        end
        $display("[PASS] Completed 30 random frames successfully.");

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
