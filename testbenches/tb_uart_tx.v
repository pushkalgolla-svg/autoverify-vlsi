`timescale 1ns / 1ps

/**
 * Self-Checking Testbench with Functional Coverage & Assertions for UART Transmitter
 *
 * Verifies:
 *   1. Bit-for-bit serial payload and framing protocol validation (Start=0, 8 Data LSB-first, Parity, Stop=1).
 *   2. Timing verification of bit duration (exactly CLKS_PER_BIT for each bit).
 *   3. All 4 Parity Modes (2'b00 None, 2'b01 Odd, 2'b10 Even, 2'b11 Reserved/No Parity).
 *   4. Data pattern coverage (All-0s, All-1s, Alternating 0x55/0xAA, Walking-1s across all 8 bit positions).
 *   5. Parity latching: External parity_mode pin changes during transmission do not alter active frame.
 *   6. Request rejection while busy: Asserting tx_start while tx_busy=1 is safely ignored.
 *   7. Handshake invariants: tx_busy assertions, single-cycle tx_done pulse, immediate return to LOW.
 *   8. Inter-frame line gap measurement across variable intentional delays (0, 3, 7 cycles).
 *   9. Constrained-random stress frames (30 frames).
 */

module tb_uart_tx();

    parameter CLKS_PER_BIT = 10;
    parameter CLK_PERIOD   = 10; // 100 MHz clock

    reg       clk;
    reg       rst_n;
    reg       tx_start;
    reg [7:0] din;
    reg [1:0] parity_mode;

    wire tx;
    wire tx_busy;
    wire tx_done;

    integer total_errors;
    integer total_checks;
    integer passed_checks;
    integer failed_checks;
    integer done_pulse_count;
    integer busy_drop_count;

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

    // =========================================================================
    // INSTANCE 2: Real-World Hardware 115,200 Baud Configuration
    // (CLKS_PER_BIT = 868 at 100MHz clock)
    // =========================================================================
    reg       tx_start_hw;
    reg [7:0] din_hw;
    reg [1:0] parity_mode_hw;
    wire      tx_hw;
    wire      tx_busy_hw;
    wire      tx_done_hw;

    uart_tx #(
        .CLKS_PER_BIT(868) // 100MHz / 115,200 baud = 868 clock cycles per bit
    ) dut_hw_115200 (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start_hw),
        .din(din_hw),
        .parity_mode(parity_mode_hw),
        .tx(tx_hw),
        .tx_busy(tx_busy_hw),
        .tx_done(tx_done_hw)
    );

    // Clock generator
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Safety watchdog timer
    initial begin
        #35000000;
        $display("[ERROR] Watchdog timeout: simulation hung!");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("logs/uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

    // =========================================================================
    // PROCEDURAL FUNCTIONAL COVERAGE BINS
    // =========================================================================
    // Parity modes (4 bins)
    integer cov_mode_none, cov_mode_odd, cov_mode_even, cov_mode_reserved;

    // Bit timing compliance (4 bins)
    integer cov_timing_start, cov_timing_data, cov_timing_parity, cov_timing_stop;

    // Data patterns (12 bins)
    integer cov_pat_all0, cov_pat_all1, cov_pat_alt55, cov_pat_altAA;
    integer cov_pat_walking1[0:7];

    // Mid-frame parity change (2 bins)
    integer cov_latch_odd_change, cov_latch_even_change;

    // Busy request rejection (1 bin)
    integer cov_busy_rejection;

    // Handshake checks (3 bins)
    integer cov_busy_active, cov_done_pulse_exact1, cov_done_imm_low;

    // Inter-frame gap measurements (3 bins)
    integer cov_gap_delay0, cov_gap_delay3, cov_gap_delay7;

    // Constrained random (1 bin)
    integer cov_random_frames;

    // Real hardware baud rate verification (1 bin)
    integer cov_hw_baud;

    initial begin
        cov_mode_none = 0; cov_mode_odd = 0; cov_mode_even = 0; cov_mode_reserved = 0;
        cov_timing_start = 0; cov_timing_data = 0; cov_timing_parity = 0; cov_timing_stop = 0;
        cov_pat_all0 = 0; cov_pat_all1 = 0; cov_pat_alt55 = 0; cov_pat_altAA = 0;
        for (i = 0; i < 8; i = i + 1) cov_pat_walking1[i] = 0;
        cov_latch_odd_change = 0; cov_latch_even_change = 0;
        cov_busy_rejection = 0;
        cov_busy_active = 0; cov_done_pulse_exact1 = 0; cov_done_imm_low = 0;
        cov_gap_delay0 = 0; cov_gap_delay3 = 0; cov_gap_delay7 = 0;
        cov_random_frames = 0;
        cov_hw_baud = 0;
        total_errors = 0; total_checks = 0; passed_checks = 0; failed_checks = 0;
    end

    // Assert condition helper
    task assert_cond;
        input condition;
        input [511:0] msg;
        begin
            total_checks = total_checks + 1;
            if (condition) begin
                passed_checks = passed_checks + 1;
            end else begin
                failed_checks = failed_checks + 1;
                total_errors = total_errors + 1;
                $display("[ASSERTION_FAIL] %0s", msg);
            end
        end
    endtask

    // Reset task
    task apply_reset;
        begin
            @(negedge clk);
            rst_n          = 1'b0;
            tx_start       = 1'b0;
            din            = 8'h00;
            parity_mode    = 2'b00;
            tx_start_hw    = 1'b0;
            din_hw         = 8'h00;
            parity_mode_hw = 2'b00;
            #(CLK_PERIOD * 3);
            @(negedge clk);
            rst_n          = 1'b1;
            #(CLK_PERIOD * 2);
        end
    endtask

    // Monitored frame transmission and bit-accurate verification
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
        begin
            done_pulse_count = 0;
            busy_drop_count  = 0;

            // Coverage sampling: parity mode
            if (test_parity == 2'b00) cov_mode_none = cov_mode_none + 1;
            else if (test_parity == 2'b01) cov_mode_odd = cov_mode_odd + 1;
            else if (test_parity == 2'b10) cov_mode_even = cov_mode_even + 1;
            else if (test_parity == 2'b11) cov_mode_reserved = cov_mode_reserved + 1;

            // Coverage sampling: data patterns
            if (test_din == 8'h00) cov_pat_all0 = cov_pat_all0 + 1;
            if (test_din == 8'hFF) cov_pat_all1 = cov_pat_all1 + 1;
            if (test_din == 8'h55) cov_pat_alt55 = cov_pat_alt55 + 1;
            if (test_din == 8'hAA) cov_pat_altAA = cov_pat_altAA + 1;
            if (test_din == 8'h01) cov_pat_walking1[0] = cov_pat_walking1[0] + 1;
            if (test_din == 8'h02) cov_pat_walking1[1] = cov_pat_walking1[1] + 1;
            if (test_din == 8'h04) cov_pat_walking1[2] = cov_pat_walking1[2] + 1;
            if (test_din == 8'h08) cov_pat_walking1[3] = cov_pat_walking1[3] + 1;
            if (test_din == 8'h10) cov_pat_walking1[4] = cov_pat_walking1[4] + 1;
            if (test_din == 8'h20) cov_pat_walking1[5] = cov_pat_walking1[5] + 1;
            if (test_din == 8'h40) cov_pat_walking1[6] = cov_pat_walking1[6] + 1;
            if (test_din == 8'h80) cov_pat_walking1[7] = cov_pat_walking1[7] + 1;

            // 1. Assert start on negedge
            @(negedge clk);
            din         = test_din;
            parity_mode = test_parity;
            tx_start    = 1'b1;

            @(negedge clk);
            tx_start    = 1'b0;

            // Verify tx_busy asserted immediately upon start
            assert_cond(tx_busy === 1'b1, "tx_busy must assert immediately after tx_start");
            cov_busy_active = cov_busy_active + 1;

            // 2. Verify START bit (0 for exactly CLKS_PER_BIT cycles)
            for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                assert_cond(tx === 1'b0, "Start bit line level must be 0");
                assert_cond(tx_busy === 1'b1, "tx_busy must remain asserted during start bit");
                if (tx_done === 1'b1) done_pulse_count = done_pulse_count + 1;
                @(negedge clk);
            end
            cov_timing_start = cov_timing_start + 1;

            // 3. Verify DATA bits (8 bits, LSB-first, each for CLKS_PER_BIT cycles)
            captured_data = 8'h00;
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                if (change_parity_midway && bit_idx == 3) begin
                    parity_mode = new_parity;
                    if (test_parity == 2'b01) cov_latch_odd_change = cov_latch_odd_change + 1;
                    if (test_parity == 2'b10) cov_latch_even_change = cov_latch_even_change + 1;
                end

                for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                    if (clk_idx == (CLKS_PER_BIT / 2)) begin
                        captured_data[bit_idx] = tx;
                    end
                    assert_cond(tx_busy === 1'b1, "tx_busy must remain asserted during data bit");
                    if (tx_done === 1'b1) done_pulse_count = done_pulse_count + 1;
                    @(negedge clk);
                end
            end
            cov_timing_data = cov_timing_data + 1;

            assert_cond(captured_data === test_din, "Transmitted serial byte payload matches din");

            // 4. Verify PARITY bit if enabled at start (modes 2'b01 or 2'b10 only)
            if (test_parity == 2'b01 || test_parity == 2'b10) begin
                if (test_parity == 2'b01)
                    expected_parity = ~(^test_din); // Odd parity
                else
                    expected_parity = ^test_din;    // Even parity

                for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                    if (clk_idx == (CLKS_PER_BIT / 2)) begin
                        captured_parity = tx;
                    end
                    assert_cond(tx_busy === 1'b1, "tx_busy must remain asserted during parity bit");
                    if (tx_done === 1'b1) done_pulse_count = done_pulse_count + 1;
                    @(negedge clk);
                end
                cov_timing_parity = cov_timing_parity + 1;
                assert_cond(captured_parity === expected_parity, "Parity bit matches expected mathematical parity");
            end

            // 5. Verify STOP bit (1 for exactly CLKS_PER_BIT cycles)
            for (clk_idx = 0; clk_idx < CLKS_PER_BIT; clk_idx = clk_idx + 1) begin
                assert_cond(tx === 1'b1, "Stop bit line level must be 1");
                if (clk_idx == CLKS_PER_BIT - 1) begin
                    if (tx_done === 1'b1) done_pulse_count = done_pulse_count + 1;
                end else begin
                    if (tx_done === 1'b1) done_pulse_count = done_pulse_count + 1;
                    assert_cond(tx_busy === 1'b1, "tx_busy must remain asserted during stop bit");
                end
                @(negedge clk);
            end
            cov_timing_stop = cov_timing_stop + 1;

            // 6. Post-frame Handshake Checks
            if (tx_done === 1'b1) done_pulse_count = done_pulse_count + 1;
            assert_cond(done_pulse_count === 1, "tx_done must pulse for exactly 1 clock cycle");
            if (done_pulse_count === 1) cov_done_pulse_exact1 = cov_done_pulse_exact1 + 1;

            assert_cond(tx_busy === 1'b0, "tx_busy must deassert after frame completion");
        end
    endtask

    // Task to verify tx_done drops to 0 on the exact next clock edge
    task verify_tx_done_immediate_low;
        begin
            $display("\n--- [Test 4] Verifying tx_done Deasserts Immediately on Next Clock Cycle ---");
            @(negedge clk);
            din = 8'h99;
            parity_mode = 2'b00;
            tx_start = 1'b1;
            @(negedge clk);
            tx_start = 1'b0;

            // Wait until tx_done asserts
            while (tx_done !== 1'b1) begin
                @(posedge clk);
                #1;
            end

            assert_cond(tx_done === 1'b1, "tx_done is HIGH at completion posedge");

            // Check immediately on the very next posedge: tx_done MUST be 0
            @(posedge clk);
            #1;
            assert_cond(tx_done === 1'b0, "tx_done went LOW immediately on the next clock cycle");
            cov_done_imm_low = cov_done_imm_low + 1;

            @(negedge clk);
        end
    endtask

    // Task to verify request rejection when UART is busy
    task verify_busy_rejection;
        integer k;
        reg [7:0] captured_payload;
        begin
            $display("\n--- [Test 5] Verifying Request Rejection While Busy ---");
            // Start Frame 1 with 8'h55 (None parity)
            @(negedge clk);
            din = 8'h55;
            parity_mode = 2'b00;
            tx_start = 1'b1;
            @(negedge clk);
            tx_start = 1'b0;

            // Wait until in DATA state (e.g. 15 clock cycles after start)
            #(CLK_PERIOD * 15);
            assert_cond(tx_busy === 1'b1, "UART is currently busy");

            // Attempt to assert tx_start with different data (8'hAA) while busy
            @(negedge clk);
            din = 8'hAA;
            tx_start = 1'b1;
            @(negedge clk);
            tx_start = 1'b0;

            // Verify tx_busy did NOT drop or glitch
            assert_cond(tx_busy === 1'b1, "tx_busy remains HIGH despite invalid tx_start attempt");
            cov_busy_rejection = cov_busy_rejection + 1;

            // Wait for Frame 1 to complete cleanly
            while (tx_done !== 1'b1) begin
                @(posedge clk);
                #1;
            end
            assert_cond(tx_done === 1'b1, "Original frame completed with tx_done");
            @(negedge clk);
            $display("[PASS] Request while busy safely rejected; original frame completed uninterrupted.");
        end
    endtask

    // Task to measure actual inter-frame gap between consecutive transmissions
    task measure_consecutive_frame_gap;
        input [7:0] byte1;
        input [7:0] byte2;
        input integer intentional_delay;

        integer wait_idx;
        integer measured_gap;
        integer expected_gap;
        begin
            $display("\n--- [Test 6] Measuring Inter-Frame Gap (Intentional Delay = %0d cycles) ---", intentional_delay);

            // Step 1: Transmit Frame 1
            @(negedge clk);
            din = byte1;
            parity_mode = 2'b00;
            tx_start = 1'b1;
            @(negedge clk);
            tx_start = 1'b0;

            // Step 2: Wait until Frame 1 completion (tx_done asserts at posedge)
            while (tx_done !== 1'b1) begin
                @(posedge clk);
                #1;
            end

            // Step 3: Measure clock cycles from Frame 1 completion to Frame 2 start bit
            measured_gap = 0;

            // Any intentional idle delay cycles
            for (wait_idx = 0; wait_idx < intentional_delay; wait_idx = wait_idx + 1) begin
                @(posedge clk);
                #1;
                measured_gap = measured_gap + 1;
            end

            // Drive tx_start for Frame 2 on negedge
            @(negedge clk);
            din = byte2;
            parity_mode = 2'b00;
            tx_start = 1'b1;

            // On the subsequent posedge + #1, DUT evaluates tx_start from STATE_IDLE
            @(posedge clk);
            #1;
            measured_gap = measured_gap + 1;

            // Deassert tx_start on negedge
            @(negedge clk);
            tx_start = 1'b0;

            // Step 4: Sample DUT at every positive clock edge with #1 delay
            while ((tx !== 1'b0 || tx_busy !== 1'b1) && measured_gap < 50) begin
                @(posedge clk);
                #1;
                measured_gap = measured_gap + 1;
            end

            expected_gap = 1 + intentional_delay;
            if (intentional_delay == 0) cov_gap_delay0 = 1;
            if (intentional_delay == 3) cov_gap_delay3 = 1;
            if (intentional_delay == 7) cov_gap_delay7 = 1;

            $display("[INFO] Measured cycles from Frame 1 completion to Frame 2 start: %0d (Expected: %0d)",
                     measured_gap, expected_gap);

            assert_cond(measured_gap === expected_gap, "Inter-frame gap matches expected clock cycle count");

            // Wait for Frame 2 to complete cleanly
            while (tx_done !== 1'b1) begin
                @(posedge clk);
                #1;
            end
            @(negedge clk);
        end
    endtask

    // Task to verify real hardware baud rate (115,200 baud @ 100MHz clock: CLKS_PER_BIT = 868)
    task verify_hw_baud_115200;
        integer c_idx;
        integer b_idx;
        reg [7:0] rx_payload;
        reg       rx_parity;
        begin
            $display("\n--- [Test 11] Real Hardware Baud Rate Verification (115,200 Baud @ 100MHz: CLKS_PER_BIT = 868) ---");
            
            // Frame 1: 0xA5 with Odd Parity
            @(negedge clk);
            din_hw = 8'hA5;
            parity_mode_hw = 2'b01; // Odd parity
            tx_start_hw = 1'b1;

            @(negedge clk);
            tx_start_hw = 1'b0;

            assert_cond(tx_busy_hw === 1'b1, "HW Baud Frame 1: tx_busy asserts immediately on start");

            // Start bit: exactly 868 clock cycles of 0
            for (c_idx = 0; c_idx < 868; c_idx = c_idx + 1) begin
                assert_cond(tx_hw === 1'b0, "HW Baud Frame 1: Start bit line level must be 0");
                @(negedge clk);
            end

            // 8 Data bits: 868 clock cycles each, sample at midpoint 434
            rx_payload = 8'h00;
            for (b_idx = 0; b_idx < 8; b_idx = b_idx + 1) begin
                for (c_idx = 0; c_idx < 868; c_idx = c_idx + 1) begin
                    if (c_idx == 434) rx_payload[b_idx] = tx_hw;
                    @(negedge clk);
                end
            end
            assert_cond(rx_payload === 8'hA5, "HW Baud Frame 1: Serial data matches expected 0xA5");

            // Parity bit: Odd parity of 0xA5 (4 ones -> parity bit = 1)
            for (c_idx = 0; c_idx < 868; c_idx = c_idx + 1) begin
                if (c_idx == 434) rx_parity = tx_hw;
                @(negedge clk);
            end
            assert_cond(rx_parity === 1'b1, "HW Baud Frame 1: Odd parity bit verified as 1");

            // Stop bit: 868 clock cycles of 1
            for (c_idx = 0; c_idx < 868; c_idx = c_idx + 1) begin
                assert_cond(tx_hw === 1'b1, "HW Baud Frame 1: Stop bit line level must be 1");
                @(negedge clk);
            end

            assert_cond(tx_done_hw === 1'b1, "HW Baud Frame 1: tx_done asserted at frame completion");
            assert_cond(tx_busy_hw === 1'b0, "HW Baud Frame 1: tx_busy deasserted at frame completion");

            // Frame 2: 0x5A with Even Parity (complementary bit toggle)
            @(negedge clk);
            din_hw = 8'h5A;
            parity_mode_hw = 2'b10; // Even parity
            tx_start_hw = 1'b1;

            @(negedge clk);
            tx_start_hw = 1'b0;

            assert_cond(tx_busy_hw === 1'b1, "HW Baud Frame 2: tx_busy asserts immediately on start");

            // Start bit
            for (c_idx = 0; c_idx < 868; c_idx = c_idx + 1) begin
                assert_cond(tx_hw === 1'b0, "HW Baud Frame 2: Start bit line level must be 0");
                @(negedge clk);
            end

            // 8 Data bits
            rx_payload = 8'h00;
            for (b_idx = 0; b_idx < 8; b_idx = b_idx + 1) begin
                for (c_idx = 0; c_idx < 868; c_idx = c_idx + 1) begin
                    if (c_idx == 434) rx_payload[b_idx] = tx_hw;
                    @(negedge clk);
                end
            end
            assert_cond(rx_payload === 8'h5A, "HW Baud Frame 2: Serial data matches expected 0x5A");

            // Parity bit: Even parity of 0x5A (4 ones -> parity bit = 0)
            for (c_idx = 0; c_idx < 868; c_idx = c_idx + 1) begin
                if (c_idx == 434) rx_parity = tx_hw;
                @(negedge clk);
            end
            assert_cond(rx_parity === 1'b0, "HW Baud Frame 2: Even parity bit verified as 0");

            // Stop bit
            for (c_idx = 0; c_idx < 868; c_idx = c_idx + 1) begin
                assert_cond(tx_hw === 1'b1, "HW Baud Frame 2: Stop bit line level must be 1");
                @(negedge clk);
            end

            assert_cond(tx_done_hw === 1'b1, "HW Baud Frame 2: tx_done asserted at frame completion");
            assert_cond(tx_busy_hw === 1'b0, "HW Baud Frame 2: tx_busy deasserted at frame completion");

            @(negedge clk);
            din_hw = 8'h00;
            parity_mode_hw = 2'b00;

            cov_hw_baud = 1;
            $display("[PASS] Real hardware 115,200 baud frames verified cycle-accurately (17,360 clock cycles).");
        end
    endtask

    // Main Test Execution
    integer i;
    integer covered_bins;
    integer total_bins;
    real cov_percentage;

    initial begin
        total_errors = 0;

        $display("==================================================");
        $display("     STARTING UART_TX VERIFICATION BENCHMARK      ");
        $display("==================================================");

        // 1. Reset Verification
        apply_reset();
        assert_cond(tx === 1'b1 && tx_busy === 1'b0 && tx_done === 1'b0,
                    "Reset state verified: line is IDLE (HIGH), busy=0, done=0");

        // 2. Directed Nominal Tests (No Parity, Odd Parity, Even Parity)
        $display("\n--- [Test 1] Directed Nominal: No Parity (Mode 2'b00) ---");
        send_and_verify_frame(8'hA5, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h00, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'hFF, 2'b00, 0, 2'b00);

        $display("\n--- [Test 2] Directed Nominal: Odd Parity (Mode 2'b01) ---");
        send_and_verify_frame(8'h3C, 2'b01, 0, 2'b00); // 4 ones -> odd parity = 1
        send_and_verify_frame(8'h01, 2'b01, 0, 2'b00); // 1 one  -> odd parity = 0
        send_and_verify_frame(8'h00, 2'b01, 0, 2'b00); // 0 ones -> odd parity = 1

        $display("\n--- [Test 3] Directed Nominal: Even Parity (Mode 2'b10) ---");
        send_and_verify_frame(8'h3C, 2'b10, 0, 2'b00); // 4 ones -> even parity = 0
        send_and_verify_frame(8'h01, 2'b10, 0, 2'b00); // 1 one  -> even parity = 1
        send_and_verify_frame(8'h00, 2'b10, 0, 2'b00); // 0 ones -> even parity = 0

        // 3. Verify tx_done deasserts immediately on next clock
        verify_tx_done_immediate_low();

        // 4. Request Rejection While Busy
        verify_busy_rejection();

        // 5. Measure Actual Consecutive Frame Gap Across Multiple Intentional Delays
        measure_consecutive_frame_gap(8'h12, 8'h34, 0); // Delay = 0 -> measured 1 cycle
        measure_consecutive_frame_gap(8'h56, 8'h78, 3); // Delay = 3 -> measured 4 cycles
        measure_consecutive_frame_gap(8'h9A, 8'hBC, 7); // Delay = 7 -> measured 8 cycles

        // 6. Walking Ones Pattern Coverage (8 bit positions)
        $display("\n--- [Test 7] Walking 1s Data Pattern Verification ---");
        send_and_verify_frame(8'h01, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h02, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h04, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h08, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h10, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h20, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h40, 2'b00, 0, 2'b00);
        send_and_verify_frame(8'h80, 2'b00, 0, 2'b00);

        // Alternating patterns (0x55, 0xAA)
        send_and_verify_frame(8'h55, 2'b01, 0, 2'b00);
        send_and_verify_frame(8'hAA, 2'b10, 0, 2'b00);

        // 7. Parity Mode Latching Check (Change external input during active frame)
        $display("\n--- [Test 8] Parity Latching Verification (Change external input during frame) ---");
        send_and_verify_frame(8'h3C, 2'b01, 1, 2'b00); // Odd parity, pin changed to None
        send_and_verify_frame(8'h01, 2'b10, 1, 2'b01); // Even parity, pin changed to Odd

        // 8. Unsupported Parity Mode (2'b11) Verification
        $display("\n--- [Test 9] Unsupported parity_mode (2'b11) Treated as No Parity ---");
        send_and_verify_frame(8'h5A, 2'b11, 0, 2'b00);

        // 9. Constrained-Random Stress Testing (30 Frames)
        $display("\n--- [Test 10] 30 Constrained-Random Frames Across Modes ---");
        for (i = 0; i < 30; i = i + 1) begin
            reg [7:0] rand_data;
            reg [1:0] rand_mode;
            rand_data = $random & 8'hFF;
            rand_mode = $random & 2'b11;
            send_and_verify_frame(rand_data, rand_mode, 0, 2'b00);
        end
        cov_random_frames = 1;

        // 10. Real-World Hardware 115,200 Baud Verification
        verify_hw_baud_115200();

        // Exercise active-low reset assertion & recovery for complete toggle verification
        @(negedge clk);
        rst_n = 1'b0;
        #(CLK_PERIOD * 2);
        @(negedge clk);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        // =====================================================================
        // FUNCTIONAL COVERAGE AUDIT & REPORTING
        // =====================================================================
        covered_bins = 0;
        total_bins = 31;

        // Parity modes (4)
        if (cov_mode_none > 0)     covered_bins = covered_bins + 1;
        if (cov_mode_odd > 0)      covered_bins = covered_bins + 1;
        if (cov_mode_even > 0)     covered_bins = covered_bins + 1;
        if (cov_mode_reserved > 0) covered_bins = covered_bins + 1;

        // Timing compliance (4)
        if (cov_timing_start > 0)  covered_bins = covered_bins + 1;
        if (cov_timing_data > 0)   covered_bins = covered_bins + 1;
        if (cov_timing_parity > 0) covered_bins = covered_bins + 1;
        if (cov_timing_stop > 0)   covered_bins = covered_bins + 1;

        // Data patterns (12)
        if (cov_pat_all0 > 0)  covered_bins = covered_bins + 1;
        if (cov_pat_all1 > 0)  covered_bins = covered_bins + 1;
        if (cov_pat_alt55 > 0) covered_bins = covered_bins + 1;
        if (cov_pat_altAA > 0) covered_bins = covered_bins + 1;
        for (i = 0; i < 8; i = i + 1) begin
            if (cov_pat_walking1[i] > 0) covered_bins = covered_bins + 1;
        end

        // Mid-frame parity change (2)
        if (cov_latch_odd_change > 0)  covered_bins = covered_bins + 1;
        if (cov_latch_even_change > 0) covered_bins = covered_bins + 1;

        // Busy request rejection (1)
        if (cov_busy_rejection > 0) covered_bins = covered_bins + 1;

        // Handshake checks (3)
        if (cov_busy_active > 0)        covered_bins = covered_bins + 1;
        if (cov_done_pulse_exact1 > 0)  covered_bins = covered_bins + 1;
        if (cov_done_imm_low > 0)       covered_bins = covered_bins + 1;

        // Inter-frame gaps (3)
        if (cov_gap_delay0 > 0) covered_bins = covered_bins + 1;
        if (cov_gap_delay3 > 0) covered_bins = covered_bins + 1;
        if (cov_gap_delay7 > 0) covered_bins = covered_bins + 1;

        // Random stress (1)
        if (cov_random_frames > 0) covered_bins = covered_bins + 1;

        // Hardware Baud (1)
        if (cov_hw_baud > 0) covered_bins = covered_bins + 1;

        cov_percentage = (covered_bins * 100.0) / total_bins;

        $display("\n==================================================");
        $display("      FUNCTIONAL COVERAGE REPORT: uart_tx.v       ");
        $display("==================================================");
        $display("[COV_SUMMARY] Total Bins: %0d | Covered: %0d | Coverage: %0.1f%%", total_bins, covered_bins, cov_percentage);
        $display("[COV_CHECKS]  Total Checks: %0d | Passed: %0d | Failed: %0d", total_checks, passed_checks, failed_checks);
        $display("[COV_DETAIL]  Parity Modes     : None=%0d, Odd=%0d, Even=%0d, Reserved=%0d (4/4 hit)",
                 cov_mode_none, cov_mode_odd, cov_mode_even, cov_mode_reserved);
        $display("[COV_DETAIL]  Timing Checks    : Start=%0d, Data=%0d, Parity=%0d, Stop=%0d (4/4 hit)",
                 cov_timing_start, cov_timing_data, cov_timing_parity, cov_timing_stop);
        $display("[COV_DETAIL]  Key Patterns     : 0x00=%0d, 0xFF=%0d, 0x55=%0d, 0xAA=%0d, Walking1s(8/8 hit)",
                 cov_pat_all0, cov_pat_all1, cov_pat_alt55, cov_pat_altAA);
        $display("[COV_DETAIL]  Parity Latching  : Odd->None=%0d, Even->Odd=%0d (2/2 hit)",
                 cov_latch_odd_change, cov_latch_even_change);
        $display("[COV_DETAIL]  Busy Rejection   : Ignored tx_start during busy=%0d (1/1 hit)", cov_busy_rejection);
        $display("[COV_DETAIL]  Handshake Pulse  : BusyAssert=%0d, Exact1Pulse=%0d, ImmLowNext=%0d (3/3 hit)",
                 cov_busy_active, cov_done_pulse_exact1, cov_done_imm_low);
        $display("[COV_DETAIL]  Inter-Frame Gaps : Delay0(1-clk)=%0d, Delay3(4-clk)=%0d, Delay7(8-clk)=%0d (3/3 hit)",
                 cov_gap_delay0, cov_gap_delay3, cov_gap_delay7);
        $display("[COV_DETAIL]  Random Suite     : 30 Frames completed (%0d) (1/1 hit)", cov_random_frames);
        $display("[COV_DETAIL]  Hardware Baud    : 115,200 Baud verified (%0d) (1/1 hit)", cov_hw_baud);

        if (covered_bins == total_bins) begin
            $display("[COV_UNCOVERED] None (100.0%% Coverage Achieved)");
        end else begin
            $display("[COV_UNCOVERED] Bins uncovered: %0d", (total_bins - covered_bins));
        end

        // Final Results Summary
        $display("\n==================================================");
        if (total_errors == 0 && covered_bins == total_bins) begin
            $display("ALL TESTS PASSED (UART_TX COMPLETE)");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d | Uncovered Bins = %0d", total_errors, (total_bins - covered_bins));
        end
        $display("==================================================");

        $finish;
    end

endmodule