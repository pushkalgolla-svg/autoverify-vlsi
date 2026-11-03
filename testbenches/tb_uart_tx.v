`timescale 1ns / 1ps

// Testbench for uart_tx module
module tb_uart_tx;

    // Testbench parameters
    parameter CLOCK_PERIOD = 10; // 10ns clock period (100 MHz)

    // DUT signals
    reg        clk;
    reg        rst_n;
    reg        tx_start;
    reg  [7:0] din;
    reg  [1:0] parity_mode;

    wire       tx;
    wire       tx_busy;
    wire       tx_done;

    // Testbench internal variables
    integer error_count;
    integer i; // Loop variable for random tests
    integer rand_data;
    integer rand_parity;

    // Instantiate the DUT
    uart_tx #(
        .CLKS_PER_BIT (10) // Use 10 clocks per bit for faster simulation
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .tx_start    (tx_start),
        .din         (din),
        .parity_mode (parity_mode),
        .tx          (tx),
        .tx_busy     (tx_busy),
        .tx_done     (tx_done)
    );

    // Clock generator
    always # (CLOCK_PERIOD / 2) clk = ~clk;

    // Task to send a byte and verify the UART output
    // This task simulates a UART receiver and performs checks at various stages
    task send_and_verify;
        input [7:0]  data_to_send;
        input [1:0]  parity_mode_to_send;
        
        reg [7:0]    received_data;
        reg          received_parity;
        reg          calculated_parity;
        reg          is_parity_enabled;
        integer      bit_idx;
        
        // Timing calculation based on DUT's CLKS_PER_BIT
        integer      half_bit_delay_ns;
        
        // Internal variables for post-transmission checks
        reg tx_done_observed;
        reg tx_busy_observed_low;
        reg tx_line_high_during_stop_at_midpoint;
        integer clk_cycle_count;

        begin // task block
            half_bit_delay_ns = (dut.CLKS_PER_BIT / 2) * CLOCK_PERIOD;

            $display("------------------------------------------------------------------");
            $display("[TEST] %t: Sending data 0x%h with parity mode %b...", $time, data_to_send, parity_mode_to_send);

            // Drive inputs
            din         = data_to_send;
            parity_mode = parity_mode_to_send;
            tx_start    = 1'b1;
            
            // Wait for one clock cycle for inputs to register (tx_start is sampled on posedge clk)
            @(posedge clk) begin end 
            tx_start    = 1'b0;

            // Check tx_busy assertion
            if (dut.tx_busy != 1'b1) begin
                $display("[FAIL] %t: tx_busy did not go HIGH after tx_start for data 0x%h, parity_mode %b.", $time, data_to_send, parity_mode_to_send);
                error_count = error_count + 1;
            end

            // --- Verify Start Bit ---
            // The DUT sets tx_idle = 1'b1 in IDLE and tx = 1'b0 at the first clk in START state.
            // So by now (after tx_start and one posedge clk), tx should be 0.
            if (tx != 1'b0) begin
                $display("[FAIL] %t: Initial tx line is not LOW (start bit). Expected 0, Got %b. Data 0x%h, parity_mode %b.", $time, tx, data_to_send, parity_mode_to_send);
                error_count = error_count + 1;
            end
            
            // Wait to sample in the middle of the start bit
            # half_bit_delay_ns;
            if (tx != 1'b0) begin
                $display("[FAIL] %t: Start bit expected LOW at midpoint, got %b. Data 0x%h, parity_mode %b.", $time, tx, data_to_send, parity_mode_to_send);
                error_count = error_count + 1;
            end
            // Wait for the rest of the start bit period
            # half_bit_delay_ns; // Advance to the start of the first data bit

            // --- Verify Data Bits (LSB first) ---
            received_data = 8'h00;
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                # half_bit_delay_ns; // Sample in the middle of the bit
                received_data[bit_idx] = tx;
                if (tx != data_to_send[bit_idx]) begin
                    $display("[FAIL] %t: Data bit %0d mismatch. Expected %b, Got %b. Data 0x%h, parity_mode %b.", $time, bit_idx, data_to_send[bit_idx], tx, data_to_send, parity_mode_to_send);
                    error_count = error_count + 1;
                end
                # half_bit_delay_ns; // Advance to the start of the next bit
            end

            // --- Verify Parity Bit (if enabled) ---
            is_parity_enabled = (parity_mode_to_send != 2'b00);
            if (is_parity_enabled) begin // if parity_mode is not 'None'
                // Calculate expected parity (match DUT's logic)
                calculated_parity = 1'b0;
                if (parity_mode_to_send == 2'b01) begin // Odd parity
                    calculated_parity = ~(^data_to_send);
                end else if (parity_mode_to_send == 2'b10) begin // Even parity
                    calculated_parity = (^data_to_send);
                end

                # half_bit_delay_ns; // Sample in the middle of parity bit
                received_parity = tx;
                if (received_parity != calculated_parity) begin
                    $display("[FAIL] %t: Parity bit mismatch. Expected %b, Got %b. Data 0x%h, mode %b.", $time, calculated_parity, received_parity, data_to_send, parity_mode_to_send);
                    error_count = error_count + 1;
                end else begin
                    $display("[PASS] %t: Parity bit %b matched for data 0x%h, mode %b.", $time, calculated_parity, data_to_send, parity_mode_to_send);
                end
                # half_bit_delay_ns; // Advance to the start of the stop bit
            end
            
            // --- Verify Stop Bit and tx_done/tx_busy ---
            // Monitor tx, tx_done, tx_busy for the full expected duration of the stop bit.
            // The DUT bug (STATE_STOP, clk_count < 2) makes the stop bit shorter.
            // The testbench should detect this by monitoring the tx line going low prematurely,
            // or by tx_done/tx_busy asserting/deasserting too early.
            
            tx_done_observed = 1'b0;
            tx_busy_observed_low = 1'b0;
            tx_line_high_during_stop_at_midpoint = 1'b0; // Will be set if high at midpoint

            // Sample tx line at the midpoint of the *expected* stop bit period
            # half_bit_delay_ns;
            if (tx == 1'b1) begin
                tx_line_high_during_stop_at_midpoint = 1'b1;
            end
            if (tx_done) begin
                tx_done_observed = 1'b1;
            end
            if (!tx_busy) begin
                tx_busy_observed_low = 1'b1;
            end
            # half_bit_delay_ns; // Complete the first expected clock cycles of stop bit
            
            // Continue monitoring until the end of the expected stop bit period.
            // This loop captures any state changes regardless of the bug.
            for (clk_cycle_count = 1; clk_cycle_count < dut.CLKS_PER_BIT; clk_cycle_count = clk_cycle_count + 1) begin
                @(posedge clk) begin
                    if (tx_done) begin
                        tx_done_observed = 1'b1;
                    end
                    if (!tx_busy) begin
                        tx_busy_observed_low = 1'b1;
                    end
                end
            end
            
            // Check results after the expected full stop bit duration
            if (!tx_line_high_during_stop_at_midpoint) begin
                $display("[FAIL] %t: Stop bit expected HIGH at midpoint, got %b. Data 0x%h, parity_mode %b.", $time, tx, data_to_send, parity_mode_to_send);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] %t: Stop bit observed HIGH at midpoint for data 0x%h, parity_mode %b.", $time, data_to_send, parity_mode_to_send);
            end

            if (!tx_done_observed) begin
                $display("[FAIL] %t: tx_done did not pulse after transmission for data 0x%h, parity_mode %b.", $time, data_to_send, parity_mode_to_send);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] %t: tx_done pulsed after transmission for data 0x%h, parity_mode %b.", $time, data_to_send, parity_mode_to_send);
            end

            if (!tx_busy_observed_low) begin
                $display("[FAIL] %t: tx_busy did not go LOW after transmission for data 0x%h, parity_mode %b.", $time, data_to_send, parity_mode_to_send);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] %t: tx_busy went LOW after transmission for data 0x%h, parity_mode %b.", $time, data_to_send, parity_mode_to_send);
            end

            // Wait one more clock cycle to ensure tx_done de-assertion and idle state
            @(posedge clk) begin end
            if (tx_done != 1'b0) begin
                $display("[FAIL] %t: tx_done did not de-assert after one clock cycle for data 0x%h, parity_mode %b.", $time, data_to_send, parity_mode_to_send);
                error_count = error_count + 1;
            end
            if (tx_busy != 1'b0) begin // Should still be low
                $display("[FAIL] %t: tx_busy unexpectedly HIGH after completion for data 0x%h, parity_mode %b.", $time, data_to_send, parity_mode_to_send);
                error_count = error_count + 1;
            end
            if (tx != 1'b1) begin // Should be high in IDLE state
                $display("[FAIL] %t: tx line not HIGH in IDLE state after completion for data 0x%h, parity_mode %b.", $time, data_to_send, parity_mode_to_send);
                error_count = error_count + 1;
            end
            $display("------------------------------------------------------------------\n");

        end // end task block
    endtask // end task

    // Test sequence
    initial begin
        // Initialize testbench variables
        clk         = 1'b0;
        rst_n       = 1'b0;
        tx_start    = 1'b0;
        din         = 8'd0;
        parity_mode = 2'b00;
        error_count = 0;

        // VCD dumping
        $dumpfile("C:/Users/91900/.gemini/antigravity/scratch/ai_verification/logs/uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
        $display("[INFO] VCD dumping enabled to uart_tx.vcd");

        // --- Reset Verification ---
        $display("\n==================================================");
        $display("[TEST] %t: Starting Reset Verification.", $time);
        $display("==================================================");
        rst_n = 1'b0;
        # (CLOCK_PERIOD * 5); // Hold reset for 5 clock cycles
        rst_n = 1'b1;
        # (CLOCK_PERIOD * 2); // Wait a couple of cycles for DUT to settle

        if (tx != 1'b1) begin
            $display("[FAIL] %t: tx line not HIGH after reset. Expected 1, Got %b.", $time, tx);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] %t: tx line is HIGH after reset.", $time);
        end
        if (tx_busy != 1'b0) begin
            $display("[FAIL] %t: tx_busy not LOW after reset. Expected 0, Got %b.", $time, tx_busy);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] %t: tx_busy is LOW after reset.", $time);
        end
        if (tx_done != 1'b0) begin
            $display("[FAIL] %t: tx_done not LOW after reset. Expected 0, Got %b.", $time, tx_done);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] %t: tx_done is LOW after reset.", $time);
        end


        // --- Directed Nominal Tests (No Parity) ---
        $display("\n==================================================");
        $display("[TEST] %t: Starting Directed Tests (No Parity).", $time);
        $display("==================================================");
        send_and_verify(8'h55, 2'b00); // 01010101
        send_and_verify(8'hAA, 2'b00); // 10101010
        send_and_verify(8'h00, 2'b00); // All zeros
        send_and_verify(8'hFF, 2'b00); // All ones
        send_and_verify(8'h01, 2'b00); // Single bit
        send_and_verify(8'h80, 2'b00); // MSB only

        // --- Directed Nominal Tests (Odd Parity) ---
        $display("\n==================================================");
        $display("[TEST] %t: Starting Directed Tests (Odd Parity).", $time);
        $display("==================================================");
        send_and_verify(8'h55, 2'b01); // 01010101 (4 ones) -> Expected Odd Parity: 1
        send_and_verify(8'hAA, 2'b01); // 10101010 (4 ones) -> Expected Odd Parity: 1
        send_and_verify(8'h01, 2'b01); // 00000001 (1 one) -> Expected Odd Parity: 0
        send_and_verify(8'h02, 2'b01); // 00000010 (1 one) -> Expected Odd Parity: 0
        send_and_verify(8'h03, 2'b01); // 00000011 (2 ones) -> Expected Odd Parity: 1

        // --- Directed Nominal Tests (Even Parity) ---
        $display("\n==================================================");
        $display("[TEST] %t: Starting Directed Tests (Even Parity).", $time);
        $display("==================================================");
        send_and_verify(8'h55, 2'b10); // 01010101 (4 ones) -> Expected Even Parity: 0
        send_and_verify(8'hAA, 2'b10); // 10101010 (4 ones) -> Expected Even Parity: 0
        send_and_verify(8'h01, 2'b10); // 00000001 (1 one) -> Expected Even Parity: 1
        send_and_verify(8'h02, 2'b10); // 00000010 (1 one) -> Expected Even Parity: 1
        send_and_verify(8'h03, 2'b10); // 00000011 (2 ones) -> Expected Even Parity: 0

        // --- Back-to-Back Transmission Tests ---
        // This is where the bug (short stop bit) is likely to cause issues,
        // as the next transmission might start before the line fully idles if tx_start is asserted.
        $display("\n==================================================");
        $display("[TEST] %t: Starting Back-to-Back Transmission Tests.", $time);
        $display("==================================================");
        send_and_verify(8'h12, 2'b00);
        send_and_verify(8'h34, 2'b00);
        send_and_verify(8'h56, 2'b01);
        send_and_verify(8'h78, 2'b10);
        send_and_verify(8'hAB, 2'b00);
        send_and_verify(8'hCD, 2'b01);
        send_and_verify(8'hEF, 2'b10);
        send_and_verify(8'h11, 2'b00);
        send_and_verify(8'h22, 2'b01);
        send_and_verify(8'h33, 2'b10);


        // --- Constrained-Random Stress Testing ---
        $display("\n==================================================");
        $display("[TEST] %t: Starting Constrained-Random Stress Tests (100 iterations).", $time);
        $display("==================================================");
        for (i = 0; i < 100; i = i + 1) begin
            rand_data = {$random}; // Use {$random} to get positive random
            rand_data = rand_data % 256; // Limit to 8-bit range (0-255)
            
            rand_parity = {$random};
            rand_parity = rand_parity % 3; // 0, 1, 2 -> mapping to 2'b00, 2'b01, 2'b10
            
            send_and_verify(rand_data, rand_parity);
        end


        // --- Final Report ---
        $display("\n==================================================");
        if (error_count == 0) begin
            $display("[PASS] %t: ALL TESTS PASSED.", $time);
        end else begin
            $display("[FAIL] %t: SIMULATION FAILED: Total Errors = %0d.", $time, error_count);
        end
        $display("==================================================");

        $finish;

    end // end initial block

endmodule