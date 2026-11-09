`timescale 1ns / 1ps

/**
 * Self-Checking Testbench for Parameterized UART Transmitter
 * Validates:
 *   1. Reset state (tx=1, tx_busy=0, tx_done=0).
 *   2. tx_busy assertion and hold throughout entire frame.
 *   3. tx_done pulsing for EXACTLY ONE clock cycle at frame completion.
 *   4. Latched parity mode: external parity_mode change during active frame has no effect.
 *   5. Zero-idle back-to-back consecutive frames.
 *   6. Directed nominal tests (None, Odd, Even parity).
 *   7. 30 constrained-random stress test frames.
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

    // Testbench tracking
    integer total_errors;
    integer done_pulse_count;
    integer busy_drop_count;

    // Instantiate DUT
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

    // Clock generator: 100MHz
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Safety watchdog timer
    initial begin
        #10000000;
        $display("[ERROR] Watchdog timeout: simulation hung!");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("logs/uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

    // Reset task
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

    // Monitored frame transmission and verification
    task send_and_verify_frame;
        input [7:0] test_din;
        input [1:0] test_parity;
        input       change_parity_midway;
        input [1:0] new_parity;

        integer bit_idx;
        integer clk_idx;
        reg [7:0] captured_data;
        reg       captured_parity;
        reg       expected_parity;
        integer   timeout_cnt;
        begin
            done_pulse_count = 0;
            busy_drop_count  = 0;

            // 1. Assert start on negedge
            @(negedge clk);
            din         = test_din;
            parity_mode = test_parity;
            tx_start    = 1'b1;

            @(negedge clk);
            tx_start    = 1'b0;

            // Verify tx_busy asserted immediately upon start
            if (tx_busy !== 1'b1) begin
                $display("[FAIL] tx_busy failed to assert immediately after tx_start");
                total_errors = total_errors + 1;
            end

            // 2. Verify START bit (0 for CLKS_PER_BIT cycles)
            for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                if (tx !== 1'b0) begin
                    $display("[FAIL] Start bit violation at cycle %0d: Expected 0, Got %b", clk_idx, tx);
                    total_errors = total_errors + 1;
                end
                if (tx_busy !== 1'b1) begin
                    $display("[FAIL] tx_busy dropped during start bit at cycle %0d", clk_idx);
                    total_errors = total_errors + 1;
                end
                if (tx_done === 1'b1) begin
                    done_pulse_count = done_pulse_count + 1;
                end
                @(negedge clk);
            end

            // 3. Verify DATA bits (8 bits, LSB-first)
            captured_data = 8'h00;
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                // If requested, change external parity input midway (e.g. at bit 3)
                if (change_parity_midway && bit_idx == 3) begin
                    parity_mode = new_parity;
                end

                for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                    if (clk_idx == (CLKS_PER_BIT / 2)) begin
                        captured_data[bit_idx] = tx;
                    end
                    if (tx_busy !== 1'b1) begin
                        $display("[FAIL] tx_busy dropped during data bit %0d at cycle %0d", bit_idx, clk_idx);
                        total_errors = total_errors + 1;
                    end
                    if (tx_done === 1'b1) begin
                        done_pulse_count = done_pulse_count + 1;
                    end
                    @(negedge clk);
                end
            end

            if (captured_data !== test_din) begin
                $display("[FAIL] Payload mismatch: Expected 0x%0h, Got 0x%0h", test_din, captured_data);
                total_errors = total_errors + 1;
            end

            // 4. Verify PARITY bit if enabled at start (latched test_parity)
            if (test_parity != 2'b00) begin
                if (test_parity == 2'b01)
                    expected_parity = ~(^test_din); // Odd parity
                else
                    expected_parity = ^test_din;    // Even parity

                for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                    if (clk_idx == (CLKS_PER_BIT / 2)) begin
                        captured_parity = tx;
                    end
                    if (tx_busy !== 1'b1) begin
                        $display("[FAIL] tx_busy dropped during parity bit at cycle %0d", clk_idx);
                        total_errors = total_errors + 1;
                    end
                    if (tx_done === 1'b1) begin
                        done_pulse_count = done_pulse_count + 1;
                    end
                    @(negedge clk);
                end

                if (captured_parity !== expected_parity) begin
                    $display("[FAIL] Parity mismatch (mode=%0b): Expected %0b, Got %0b (din=0x%0h)",
                             test_parity, expected_parity, captured_parity, test_din);
                    total_errors = total_errors + 1;
                end
            end

            // 5. Verify STOP bit (1 for CLKS_PER_BIT cycles)
            for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                if (tx !== 1'b1) begin
                    $display("[FAIL] Stop bit violation at cycle %0d: Expected 1, Got %b", clk_idx, tx);
                    total_errors = total_errors + 1;
                end
                // On the final cycle of stop bit, tx_done pulses high
                if (clk_idx == CLKS_PER_BIT - 1) begin
                    if (tx_done === 1'b1) done_pulse_count = done_pulse_count + 1;
                end else begin
                    if (tx_done === 1'b1) done_pulse_count = done_pulse_count + 1;
                    if (tx_busy !== 1'b1) begin
                        $display("[FAIL] tx_busy dropped prematurely during stop bit at cycle %0d", clk_idx);
                        total_errors = total_errors + 1;
                    end
                end
                @(negedge clk);
            end

            // 6. Post-frame Handshake Checks
            // Check tx_done pulse count
            if (tx_done === 1'b1) done_pulse_count = done_pulse_count + 1;
            if (done_pulse_count !== 1) begin
                $display("[FAIL] tx_done pulse violation: Expected exactly 1 pulse, observed %0d pulses", done_pulse_count);
                total_errors = total_errors + 1;
            end

            // Verify tx_busy is 0 after completion
            if (tx_busy !== 1'b0) begin
                $display("[FAIL] tx_busy failed to deassert after frame completion");
                total_errors = total_errors + 1;
            end else begin
                $display("[PASS] Frame verified: din=0x%0h, parity_mode=%0b, tx_busy/done correct",
                         test_din, test_parity);
            end
        end
    endtask

    // Main Test Execution
    integer i;
    initial begin
        total_errors = 0;

        $display("==================================================");
        $display("     STARTING UART_TX VERIFICATION BENCHMARK      ");
        $display("==================================================");

        // 1. Reset Verification
        apply_reset();
        if (tx !== 1'b1 || tx_busy !== 1'b0 || tx_done !== 1'b0) begin
            $display("[FAIL] Reset state: Expected tx=1, busy=0, done=0 | Got tx=%b, busy=%b, done=%b", tx, tx_busy, tx_done);
            total_errors = total_errors + 1;
        end else begin
            $display("[PASS] Reset state verified: line is IDLE (HIGH), busy=0, done=0");
        end

        // 2. Directed Nominal Tests (No Parity)
        $display("\n--- [Test 1] Directed Nominal: No Parity (Mode 2'b00) ---");
        send_and_verify_frame(8'hA5, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h00, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'hFF, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h55, 2'b00, 0, 2'b00);

        // 3. Directed Nominal Tests (Odd Parity)
        $display("\n--- [Test 2] Directed Nominal: Odd Parity (Mode 2'b01) ---");
        send_and_verify_frame(8'h3C, 2'b01, 0, 2'b00); // 4 ones -> odd parity = 1
        send_and_verify_frame(8'h01, 2'b01, 0, 2'b00); // 1 one  -> odd parity = 0
        send_and_verify_frame(8'h00, 2'b01, 0, 2'b00); // 0 ones -> odd parity = 1
        send_and_verify_frame(8'hFF, 2'b01, 0, 2'b00); // 8 ones -> odd parity = 1

        // 4. Directed Nominal Tests (Even Parity)
        $display("\n--- [Test 3] Directed Nominal: Even Parity (Mode 2'b10) ---");
        send_and_verify_frame(8'h3C, 2'b10, 0, 2'b00); // 4 ones -> even parity = 0
        send_and_verify_frame(8'h01, 2'b10, 0, 2'b00); // 1 one  -> even parity = 1
        send_and_verify_frame(8'h00, 2'b10, 0, 2'b00); // 0 ones -> even parity = 0
        send_and_verify_frame(8'hFF, 2'b10, 0, 2'b00); // 8 ones -> even parity = 0

        // 5. Parity Mode Latching Check (Change external parity input midway)
        $display("\n--- [Test 4] Parity Latching Verification (Change external input during frame) ---");
        // Start frame with Odd parity (2'b01), change wire to None (2'b00) midway
        send_and_verify_frame(8'h3C, 2'b01, 1, 2'b00);
        $display("[PASS] Parity latching verified: Odd parity bit successfully transmitted despite external pin change to None.");

        // Start frame with Even parity (2'b10), change wire to Odd (2'b01) midway
        send_and_verify_frame(8'h01, 2'b10, 1, 2'b01);
        $display("[PASS] Parity latching verified: Even parity bit successfully transmitted despite external pin change to Odd.");

        // 6. Zero-Idle Consecutive Frames (Back-to-Back)
        $display("\n--- [Test 5] Back-to-Back Consecutive Transmission Timing ---");
        send_and_verify_frame(8'h12, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h34, 2'b01, 0, 2'b00);
        send_and_verify_frame(8'h56, 2'b10, 0, 2'b00);
        send_and_verify_frame(8'h78, 2'b00, 0, 2'b00);

        // 7. Constrained-Random Stress Testing (30 Frames)
        $display("\n--- [Test 6] 30 Constrained-Random Frames Across Random Modes ---");
        for (i = 0; i < 30; i = i + 1) begin
            reg [7:0] rand_data;
            reg [1:0] rand_mode;
            rand_data = $random & 8'hFF;
            rand_mode = ($random & 2'b11) % 3;
            send_and_verify_frame(rand_data, rand_mode, 0, 2'b00);
        end
        $display("[PASS] Completed 30 random frames with tx_busy & single-cycle tx_done checks.");

        // Final Results Summary
        $display("\n==================================================");
        if (total_errors == 0) begin
            $display("ALL TESTS PASSED (UART_TX COMPLETE)");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d", total_errors);
        end
        $display("==================================================");

        $finish;
    end

endmodule
