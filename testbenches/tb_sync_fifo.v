`timescale 1ns / 1ps

// Testbench for sync_fifo
module tb_sync_fifo;

    // DUT Parameters
    localparam DATA_WIDTH = 8;
    localparam DEPTH      = 16;
    localparam ADDR_WIDTH = $clog2(DEPTH); // For DEPTH=16, ADDR_WIDTH=4

    // Testbench Control Signals (inputs to DUT)
    reg                   clk;
    reg                   rst_n;
    reg                   wr_en;
    reg  [DATA_WIDTH-1:0] din;
    reg                   rd_en;

    // DUT Outputs (wires connected to DUT)
    wire [DATA_WIDTH-1:0] dout;
    wire                  full;
    wire                  empty;
    wire                  overflow;
    wire                  underflow;
    wire [ADDR_WIDTH:0]   count; // count is ADDR_WIDTH+1 bits wide, e.g., [4:0] for DEPTH=16

    // Testbench Variables and Reference Model
    integer               error_count;
    integer               i;           // Loop counter
    integer               test_idx;    // Test case index
    integer               max_cycles;  // For random test loop
    integer               random_op;   // For random test operation selection

    // Reference model for FIFO
    reg [DATA_WIDTH-1:0] ref_mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] ref_wr_ptr;
    reg [ADDR_WIDTH-1:0] ref_rd_ptr;
    reg [$clog2(DEPTH):0] ref_count; // ADDR_WIDTH+1 bits
    reg                  ref_full;
    reg                  ref_empty;
    reg                  ref_overflow;
    reg                  ref_underflow;
    reg [DATA_WIDTH-1:0] ref_dout;
    reg                  ref_rst_n; // Internal reset state for reference model

    // Clock Generation
    always #5 clk = ~clk;

    // DUT Instantiation
    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .din(din),
        .rd_en(rd_en),
        .dout(dout),
        .full(full),
        .empty(empty),
        .overflow(overflow),
        .underflow(underflow),
        .count(count)
    );

    // --- Helper Tasks ---

    // Task to apply reset to DUT and reference model
    task reset_fifo;
        begin
            $display("--------------------------------------------------");
            $display("RESETTING FIFO...");
            wr_en = 1'b0;
            rd_en = 1'b0;
            din   = {DATA_WIDTH{1'b0}};
            rst_n = 1'b0; // Assert reset (active-low)
            ref_rst_n = 1'b0; // Assert ref model reset (synchronous reset)
            @(posedge clk);
            @(posedge clk); // Hold reset for 2 cycles
            rst_n = 1'b1; // Deassert reset
            ref_rst_n = 1'b1; // Deassert ref model reset
            $display("FIFO RESET COMPLETE.");
        end
    endtask

    // Task to update reference model state based on current testbench inputs
    // This task should be called *before* the posedge clk that updates the DUT.
    // It predicts the state of the FIFO *after* the current clock edge.
    task update_ref_model;
        begin
            // Error flags reset every cycle unless re-triggered
            ref_overflow  = 1'b0;
            ref_underflow = 1'b0;

            if (!ref_rst_n) begin // If reset is active
                ref_wr_ptr    = {ADDR_WIDTH{1'b0}};
                ref_rd_ptr    = {ADDR_WIDTH{1'b0}};
                ref_dout      = {DATA_WIDTH{1'b0}}; // Dout is reset to 0
                ref_count     = 0;
                ref_empty     = 1'b1;
                ref_full      = 1'b0;
            end else begin
                // Update empty/full based on current ref_count *before* operations for this cycle
                ref_empty = (ref_count == 0);
                ref_full  = (ref_count == DEPTH);

                case ({wr_en, rd_en})
                    2'b10: begin // Write only
                        if (!ref_full) begin
                            ref_mem[ref_wr_ptr] = din;
                            ref_wr_ptr          = ref_wr_ptr + 1'b1;
                            ref_count           = ref_count + 1'b1;
                        end else begin
                            ref_overflow        = 1'b1;
                        end
                    end

                    2'b01: begin // Read only
                        if (!ref_empty) begin
                            ref_dout            = ref_mem[ref_rd_ptr];
                            ref_rd_ptr          = ref_rd_ptr + 1'b1;
                            ref_count           = ref_count - 1'b1;
                        end else begin
                            ref_underflow       = 1'b1;
                            ref_dout            = {DATA_WIDTH{1'b0}}; // No valid data on underflow
                        end
                    end

                    2'b11: begin // Simultaneous Write and Read
                        // Logic reflects correct FIFO behavior for simultaneous R/W
                        if (ref_full) begin // FIFO is full, write is ignored, read occurs.
                            ref_overflow        = 1'b1; // Overflow on write attempt
                            ref_dout            = ref_mem[ref_rd_ptr];
                            ref_rd_ptr          = ref_rd_ptr + 1'b1;
                            ref_count           = ref_count - 1'b1;
                        end else if (ref_empty) begin // FIFO is empty, read is ignored, write occurs.
                            ref_underflow       = 1'b1; // Underflow on read attempt
                            ref_mem[ref_wr_ptr] = din;
                            ref_wr_ptr          = ref_wr_ptr + 1'b1;
                            ref_count           = ref_count + 1'b1;
                            ref_dout            = {DATA_WIDTH{1'b0}}; // No valid data read
                        end else begin // Neither full nor empty: both happen, count unchanged.
                            ref_mem[ref_wr_ptr] = din;
                            ref_wr_ptr          = ref_wr_ptr + 1'b1;
                            ref_dout            = ref_mem[ref_rd_ptr];
                            ref_rd_ptr          = ref_rd_ptr + 1'b1;
                            // ref_count remains unchanged
                        end
                    end

                    default: begin
                        // No operation, flags reset, other states unchanged
                    end
                endcase
            end
        end
    endtask

    // Task to compare DUT outputs with reference model
    // This task should be called *after* a posedge clk, when DUT outputs are stable.
    task check_fifo_state;
        begin
            @(posedge clk); // Wait for outputs to settle after operations
            $display("Time %0t: Checking FIFO state (Test #%0d)...", $time, test_idx);

            // Compare dout
            // On a valid read (rd_en asserted and not empty), dout must match ref_dout.
            // On an underflow read (rd_en asserted and empty), dout is garbage or the last value.
            // For the bug, it reads uninitialized memory. Ref_dout will be 0.
            // When no read occurs, dout holds its last value.
            if (rd_en && !empty) begin // Valid read
                if (dout !== ref_dout) begin
                    $display("[FAIL] dout mismatch on VALID READ. Expected: %h, Got: %h", ref_dout, dout);
                    error_count = error_count + 1;
                end else begin
                    $display("[PASS] dout matches on valid read: %h", dout);
                end
            end else if (rd_en && empty) begin // Underflow read
                // On underflow, ref_dout is forced to 0. DUT's dout will likely be X or garbage
                // but the DUT bug forces it to decrement count and read memory anyway.
                // Comparing dout directly against ref_dout=0 is the most robust check here.
                if (dout !== ref_dout) begin
                    $display("[FAIL] dout mismatch on UNDERFLOW READ. Expected: %h, Got: %h (DUT reads uninitialized/garbage)", ref_dout, dout);
                    error_count = error_count + 1;
                end else begin
                    $display("[PASS] dout matches on underflow read: %h", dout); // Should typically be 0
                end
            end else begin // No read or not applicable, dout should ideally retain old value or be 0 after reset
                $display("[INFO] dout was not updated by current cycle's operation, current value: %h", dout);
            end

            // Compare status flags and count
            if (full !== ref_full) begin
                $display("[FAIL] full mismatch. Expected: %b, Got: %b", ref_full, full);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] full matches: %b", full);
            end

            if (empty !== ref_empty) begin
                $display("[FAIL] empty mismatch. Expected: %b, Got: %b", ref_empty, empty);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] empty matches: %b", empty);
            end

            if (overflow !== ref_overflow) begin
                $display("[FAIL] overflow mismatch. Expected: %b, Got: %b", ref_overflow, overflow);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] overflow matches: %b", overflow);
            end

            if (underflow !== ref_underflow) begin
                $display("[FAIL] underflow mismatch. Expected: %b, Got: %b", ref_underflow, underflow);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] underflow matches: %b", underflow);
            end

            if (count !== ref_count) begin
                $display("[FAIL] count mismatch. Expected: %0d, Got: %0d", ref_count, count);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] count matches: %0d", count);
            end

            $display("--------------------------------------------------");
        end
    endtask

    // Main Test Sequence
    initial begin
        // VCD Dump Setup
        $dumpfile("C:/Users/91900/.gemini/antigravity/scratch/ai_verification/logs/sync_fifo.vcd");
        $dumpvars(0, tb_sync_fifo);

        // Initialize Testbench variables
        clk         = 1'b0;
        rst_n       = 1'b0;
        wr_en       = 1'b0;
        rd_en       = 1'b0;
        din         = {DATA_WIDTH{1'b0}};
        error_count = 0;
        test_idx    = 0;

        // Give some time for initial setup of VCD
        #100;

        // --- Test Scenario 1: Reset Verification ---
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] RESET VERIFICATION", test_idx);
        reset_fifo;
        // After reset, DUT and ref model should be empty, count=0, dout=0
        wr_en = 1'b0; rd_en = 1'b0; din = {DATA_WIDTH{1'b0}}; // Inputs for updating ref model
        update_ref_model; // Sets ref_empty=1, ref_full=0, ref_count=0, ref_dout=0
        check_fifo_state;


        // --- Test Scenario 2: Fill FIFO (Write Only) ---
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] FILL FIFO (WRITE ONLY)", test_idx);
        wr_en = 1'b1;
        rd_en = 1'b0;
        for (i = 0; i < DEPTH; i = i + 1) begin
            din = i; // Write increasing data
            $display("Time %0t: Writing data %h", $time, din);
            update_ref_model; // Update ref model *before* positive edge
            check_fifo_state; // Check on posedge, after ref model is updated
        end
        wr_en = 1'b0; // Stop writing

        // Check if FIFO is full
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] CHECK FULL STATE", test_idx);
        wr_en = 1'b0; rd_en = 1'b0; // No operations
        update_ref_model;
        check_fifo_state;


        // --- Test Scenario 3: Overflow Test (Write to Full FIFO) ---
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] OVERFLOW TEST (Write to Full FIFO)", test_idx);
        wr_en = 1'b1;
        din   = 8'hAA; // Try to write new data
        update_ref_model; // Ref model will assert ref_overflow
        check_fifo_state;
        wr_en = 1'b0; // Stop attempting write

        // Check state after overflow attempt (should still be full, overflow flag cleared)
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] CHECK STATE AFTER OVERFLOW ATTEMPT", test_idx);
        wr_en = 1'b0; rd_en = 1'b0;
        update_ref_model; // Ref model's overflow will be cleared
        check_fifo_state;

        // --- Test Scenario 4: Empty FIFO (Read Only) ---
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] EMPTY FIFO (READ ONLY)", test_idx);
        rd_en = 1'b1;
        wr_en = 1'b0;
        for (i = 0; i < DEPTH; i = i + 1) begin
            $display("Time %0t: Reading data...", $time);
            update_ref_model; // Ref model will set ref_dout to ref_mem[ref_rd_ptr] and decrement count
            check_fifo_state; // Check dout against ref_dout
        end
        rd_en = 1'b0; // Stop reading

        // Check if FIFO is empty
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] CHECK EMPTY STATE", test_idx);
        wr_en = 1'b0; rd_en = 1'b0;
        update_ref_model;
        check_fifo_state;

        // --- Test Scenario 5: Underflow Test (Read from Empty FIFO) ---
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] UNDERFLOW TEST (Read from Empty FIFO)", test_idx);
        rd_en = 1'b1;
        update_ref_model; // Ref model will assert ref_underflow, ref_dout will be 0
        check_fifo_state;
        rd_en = 1'b0; // Stop attempting read

        // Check state after underflow attempt (should still be empty, underflow flag cleared)
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] CHECK STATE AFTER UNDERFLOW ATTEMPT", test_idx);
        wr_en = 1'b0; rd_en = 1'b0;
        update_ref_model; // Ref model's underflow will be cleared
        check_fifo_state;


        // --- Test Scenario 6: Simultaneous Write and Read (Normal Operation) ---
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] SIMULTANEOUS W/R (NORMAL OPERATION)", test_idx);
        // Fill FIFO partially to half capacity
        wr_en = 1'b1;
        rd_en = 1'b0;
        for (i = 0; i < DEPTH/2; i = i + 1) begin
            din = i + 8'h10; // Write data 0x10, 0x11, etc.
            update_ref_model;
            check_fifo_state;
        end
        wr_en = 1'b0;

        // Perform simultaneous W/R, FIFO should maintain its level (DEPTH/2)
        wr_en = 1'b1;
        rd_en = 1'b1;
        for (i = 0; i < DEPTH/2; i = i + 1) begin
            din = 8'h50 + i; // New data 0x50, 0x51, etc.
            $display("Time %0t: Simultaneous W/R, Write %h, Read expected %h", $time, din, ref_dout);
            update_ref_model; // Ref model will reflect data 'passing through', count unchanged
            check_fifo_state;
        end
        wr_en = 1'b0;
        rd_en = 1'b0;

        // Check state after simultaneous ops (count should be DEPTH/2)
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] CHECK STATE AFTER SIMULTANEOUS W/R", test_idx);
        wr_en = 1'b0; rd_en = 1'b0;
        update_ref_model;
        check_fifo_state;


        // --- Test Scenario 7: Simultaneous W/R when FIFO is Full ---
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] SIMULTANEOUS W/R (FIFO FULL)", test_idx);
        // Fill FIFO completely
        wr_en = 1'b1;
        rd_en = 1'b0;
        for (i = 0; i < DEPTH/2; i = i + 1) begin // Finish filling from half full
            din = i + 8'h80; // Write data 0x80, 0x81, etc.
            update_ref_model;
            check_fifo_state;
        end
        wr_en = 1'b0; // Now FIFO is full

        // Attempt simultaneous W/R
        wr_en = 1'b1;
        rd_en = 1'b1;
        din = 8'hBB; // Attempt to write new data
        $display("Time %0t: Simultaneous W/R to FULL FIFO. Attempt write %h, Read expected %h", $time, din, ref_dout);
        update_ref_model; // Ref model expects overflow, read occurs, count--
        check_fifo_state;
        wr_en = 1'b0;
        rd_en = 1'b0;

        // Check state after (should be one less than full)
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] CHECK FIFO STATE after W/R (FIFO FULL)", test_idx);
        wr_en = 1'b0; rd_en = 1'b0;
        update_ref_model;
        check_fifo_state;

        // --- Test Scenario 8: BUG DETECTION - Simultaneous W/R when FIFO is Empty ---
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] BUG DETECTION - SIMULTANEOUS W/R (FIFO EMPTY)", test_idx);
        // Reset FIFO to ensure it's empty
        reset_fifo;
        // Check initial empty state
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] Initial state after reset (Empty)", test_idx);
        wr_en = 1'b0; rd_en = 1'b0;
        update_ref_model;
        check_fifo_state;

        // Perform simultaneous W/R when FIFO is empty
        wr_en = 1'b1;
        rd_en = 1'b1;
        din   = 8'hCC; // Data to write
        $display("Time %0t: Simultaneous W/R to EMPTY FIFO. Write %h", $time, din);
        // Reference model expects: underflow=1, count becomes 1, dout 0.
        // DUT (buggy) expects: underflow=1, count becomes DEPTH (from 0-1), dout uninitialized value (X).
        update_ref_model; // Predicts correct behavior
        check_fifo_state; // This should trigger FAIL for count and dout.
        wr_en = 1'b0;
        rd_en = 1'b0;

        // After the bug trigger, check state (ref model: 1 element, no flags set anymore)
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] CHECK STATE AFTER BUG TRIGGER", test_idx);
        wr_en = 1'b0; rd_en = 1'b0;
        update_ref_model;
        check_fifo_state;


        // --- Test Scenario 9: Constrained-Random Stress Test ---
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] CONSTRAINED-RANDOM STRESS TEST", test_idx);
        reset_fifo;
        // Check initial state
        test_idx = test_idx + 1;
        $display("\n[TEST %0d] Initial state for Random Test (Empty)", test_idx);
        wr_en = 1'b0; rd_en = 1'b0;
        update_ref_model;
        check_fifo_state;

        max_cycles = 1000;
        i = 0; // Initialize loop counter before while loop
        while (i < max_cycles) begin // Replaced for loop with while for older Icarus compatibility
            // Reset inputs for current cycle
            wr_en = 1'b0;
            rd_en = 1'b0;
            din   = $urandom; // Always provide random data

            random_op = $urandom % 4; // 0: NOP, 1: Write, 2: Read, 3: W/R

            // Simple constraint logic to avoid non-sensical operations for the random choice
            // Converted 'else if' chain to nested 'if/else begin ... end' blocks
            if ( (random_op == 1) && ref_full ) begin // If attempting to write to full FIFO
                random_op = ($urandom % 2 == 0) ? 0 : 2; // Try NOP or Read instead
            end
            else begin // Explicit else for the first condition
                if ( (random_op == 2) && ref_empty ) begin // If attempting to read from empty FIFO
                    random_op = ($urandom % 2 == 0) ? 0 : 1; // Try NOP or Write instead
                end
                else begin // Explicit else for the second condition
                    if (random_op == 3) begin // Simultaneous W/R
                        if (ref_full) begin // If full, write is ignored by ref model, essentially a read op
                            random_op = 2; // Simulate as read only
                        end
                        else begin // Explicit else for the inner if
                            if (ref_empty) begin // If empty, read is ignored by ref model, essentially a write op
                                random_op = 1; // Simulate as write only
                            end
                            // Else (neither full nor empty), keep as 3 (simultaneous). No 'else' block needed.
                        end
                    end
                end
            end

            case (random_op)
                0: begin // NOP
                    $display("Time %0t: Random Test NOP.", $time);
                end
                1: begin // Write
                    wr_en = 1'b1;
                    $display("Time %0t: Random Test Write data %h.", $time, din);
                end
                2: begin // Read
                    rd_en = 1'b1;
                    $display("Time %0t: Random Test Read.", $time);
                end
                3: begin // Simultaneous Write & Read
                    wr_en = 1'b1;
                    rd_en = 1'b1;
                    $display("Time %0t: Random Test Simultaneous W/R, Write data %h.", $time, din);
                end
            endcase

            update_ref_model; // Predict next state
            check_fifo_state; // Check DUT against predicted state
            i = i + 1; // Increment loop counter for while loop
        end // End of while loop
        wr_en = 1'b0;
        rd_en = 1'b0;

        // Final check after random test, if anything is left in FIFO, drain it
        if (count > 0) begin
            test_idx = test_idx + 1;
            $display("\n[TEST %0d] DRAIN FIFO AFTER RANDOM TEST", test_idx);
            rd_en = 1'b1;
            while (count > 0) begin
                update_ref_model;
                check_fifo_state;
            end
            rd_en = 1'b0;
        end

        // --- Simulation Summary ---
        $display("\n==================================================");
        if (error_count == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d", error_count);
        end
        $display("==================================================");

        $finish; // Terminate simulation cleanly

    end

endmodule