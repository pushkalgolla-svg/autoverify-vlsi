`timescale 1ns / 1ps

module tb_sync_fifo;

    // Testbench parameters - match DUT parameters for instantiation
    localparam DATA_WIDTH = 8;
    localparam DEPTH      = 16;
    localparam ADDR_WIDTH = $clog2(DEPTH); // For internal pointers and sizing

    // DUT signals
    reg                  clk;
    reg                  rst_n;
    reg                  wr_en;
    reg [DATA_WIDTH-1:0] din;
    reg                  rd_en;
    wire [DATA_WIDTH-1:0] dout;
    wire                  full;
    wire                  empty;
    wire                  overflow;
    wire                  underflow;
    wire [$clog2(DEPTH):0] count;

    // Internal testbench variables
    integer error_count;
    integer i, j; // Loop variables

    // Reference model for self-checking (implements correct FIFO behavior)
    reg [DATA_WIDTH-1:0] ref_fifo_mem [0:DEPTH-1]; // Simulates internal FIFO memory
    reg [ADDR_WIDTH-1:0] ref_wr_ptr_tb;            // Reference write pointer
    reg [ADDR_WIDTH-1:0] ref_rd_ptr_tb;            // Reference read pointer
    reg [$clog2(DEPTH):0] ref_count_tb;            // Reference fill level

    // Expected values for comparison with DUT outputs
    // These 'expected_' registers hold the values that the DUT *should* output
    // in the current cycle, as predicted by the reference model.
    reg [DATA_WIDTH-1:0] expected_dout;
    reg                  expected_full;
    reg                  expected_empty;
    reg                  expected_overflow;
    reg                  expected_underflow;
    reg [$clog2(DEPTH):0] expected_count;

    // Instantiate the Design Under Test (DUT)
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

    // Clock generator: 10ns period (5ns high, 5ns low)
    always #5 clk = ~clk;

    // --------------------------------------------------------------------
    // Reference Model Logic: Predicts DUT outputs based on CORRECT behavior
    // This block runs synchronously with the DUT and updates expected values.
    // --------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset reference model state
            ref_wr_ptr_tb      <= {ADDR_WIDTH{1'b0}};
            ref_rd_ptr_tb      <= {ADDR_WIDTH{1'b0}};
            ref_count_tb       <= 0;
            expected_dout      <= {DATA_WIDTH{1'b0}}; // Default output value
            expected_overflow  <= 1'b0;
            expected_underflow <= 1'b0;
            for (i=0; i<DEPTH; i=i+1) begin
                ref_fifo_mem[i] <= {DATA_WIDTH{1'b0}}; // Initialize reference memory
            end
            expected_full      = 1'b0; // Initial state: not full
            expected_empty     = 1'b1; // Initial state: empty
            expected_count     = 0;
        end else begin
            // Update combinational flags based on current ref_count_tb state
            // These are used for logic in this cycle, and for checking `full`/`empty` wires.
            expected_full  = (ref_count_tb == DEPTH);
            expected_empty = (ref_count_tb == 0);

            // Reset anticipated error flags for this cycle before re-evaluating
            expected_overflow  <= 1'b0;
            expected_underflow <= 1'b0;

            // `expected_dout` holds its previous value unless an explicit read occurs.
            // If `dout` is not updated by a read, it should remain the last valid value.

            case ({wr_en, rd_en})
                2'b10: begin // Write only
                    if (!expected_full) begin
                        ref_fifo_mem[ref_wr_ptr_tb] <= din;
                        ref_wr_ptr_tb               <= ref_wr_ptr_tb + 1'b1;
                        ref_count_tb                <= ref_count_tb + 1'b1;
                    end else begin
                        expected_overflow           <= 1'b1; // Trigger overflow
                    end
                end

                2'b01: begin // Read only
                    if (!expected_empty) begin
                        expected_dout               <= ref_fifo_mem[ref_rd_ptr_tb]; // Output data
                        ref_rd_ptr_tb               <= ref_rd_ptr_tb + 1'b1;
                        ref_count_tb                <= ref_count_tb - 1'b1;
                    end else begin
                        expected_underflow          <= 1'b1; // Trigger underflow
                        // dout should retain its previous value as no valid read occurred.
                    end
                end

                2'b11: begin // Simultaneous Write and Read - Reference model with CORRECT behavior
                    if (expected_full) begin // FIFO is full: only read, write causes overflow
                        expected_overflow           <= 1'b1;
                        expected_dout               <= ref_fifo_mem[ref_rd_ptr_tb];
                        ref_rd_ptr_tb               <= ref_rd_ptr_tb + 1'b1;
                        ref_count_tb                <= ref_count_tb - 1'b1;
                    end else if (expected_empty) begin // FIFO is empty: only write, read causes underflow
                        expected_underflow          <= 1'b1;
                        ref_fifo_mem[ref_wr_ptr_tb] <= din;
                        ref_wr_ptr_tb               <= ref_wr_ptr_tb + 1'b1;
                        ref_count_tb                <= ref_count_tb + 1'b1;
                        // dout should retain its previous value as no valid read occurred.
                    end else begin // FIFO is partially full: both write and read succeed
                        ref_fifo_mem[ref_wr_ptr_tb] <= din;
                        ref_wr_ptr_tb               <= ref_wr_ptr_tb + 1'b1;
                        expected_dout               <= ref_fifo_mem[ref_rd_ptr_tb];
                        ref_rd_ptr_tb               <= ref_rd_ptr_tb + 1'b1;
                        // ref_count_tb remains unchanged for simultaneous valid W/R
                    end
                end

                default: begin
                    // No operation. expected_dout holds previous value (as it's a `reg`).
                    // ref_count_tb and pointers also remain unchanged.
                end
            endcase
            // Update expected_count based on ref_count_tb for comparison
            expected_count = ref_count_tb;
        end
    end

    // --------------------------------------------------------------------
    // Verification Block: Compares DUT outputs with Reference Model predictions
    // Runs slightly after the clock edge to allow signals to propagate.
    // --------------------------------------------------------------------
    always @(posedge clk) begin
        #1; // Wait a small delta for combinational outputs (full, empty) to settle
            // and registered outputs (dout, count, overflow, underflow) to propagate.

        // Check dout - always compare, as `expected_dout` is precisely modeled
        if (dout !== expected_dout) begin // Using !== to catch X's or Z's
            $display("FAIL: Data output mismatch. Exp. dout = %h, Got dout = %h at time %0t (count=%0d, ref_count=%0d, wr_en=%b, rd_en=%b)",
                     expected_dout, dout, $time, count, ref_count_tb, wr_en, rd_en);
            error_count = error_count + 1;
        end

        // Check status flags and count
        if (full !== expected_full) begin
            $display("FAIL: Full flag mismatch. Exp. full = %b, Got full = %b at time %0t (count=%0d, ref_count=%0d)",
                     expected_full, full, $time, count, ref_count_tb);
            error_count = error_count + 1;
        end
        if (empty !== expected_empty) begin
            $display("FAIL: Empty flag mismatch. Exp. empty = %b, Got empty = %b at time %0t (count=%0d, ref_count=%0d)",
                     expected_empty, empty, $time, count, ref_count_tb);
            error_count = error_count + 1;
        end
        if (overflow !== expected_overflow) begin
            $display("FAIL: Overflow flag mismatch. Exp. overflow = %b, Got overflow = %b at time %0t (count=%0d, ref_count=%0d)",
                     expected_overflow, overflow, $time, count, ref_count_tb);
            error_count = error_count + 1;
        end
        if (underflow !== expected_underflow) begin
            $display("FAIL: Underflow flag mismatch. Exp. underflow = %b, Got underflow = %b at time %0t (count=%0d, ref_count=%0d)",
                     expected_underflow, underflow, $time, count, ref_count_tb);
            error_count = error_count + 1;
        end
        if (count !== expected_count) begin
            $display("FAIL: Count mismatch. Exp. count = %0d, Got count = %0d at time %0t (ref_count=%0d)",
                     expected_count, count, $time, ref_count_tb);
            error_count = error_count + 1;
        end
    end

    // --------------------------------------------------------------------
    // Test Sequencing Tasks
    // --------------------------------------------------------------------

    task reset_dut;
        begin
            $display("INFO: Resetting DUT at time %0t...", $time);
            wr_en   = 1'b0;
            rd_en   = 1'b0;
            din     = {DATA_WIDTH{1'b0}};
            rst_n   = 1'b0; // Assert reset
            @(posedge clk);
            @(posedge clk); // Hold reset for 2 clock cycles
            rst_n   = 1'b1; // De-assert reset
            @(posedge clk); // Wait one cycle for reset to propagate and initial state to settle
            $display("INFO: Reset complete at time %0t.", $time);
        end
    endtask

    task advance_clocks;
        input integer num_cycles;
        begin
            for (j=0; j<num_cycles; j=j+1) begin
                @(posedge clk);
            end
        end
    endtask

    task write_data_and_check;
        input [DATA_WIDTH-1:0] data_in;
        begin
            $display("INFO: Writing data %h at time %0t (DUT count=%0d)", data_in, $time, count);
            wr_en = 1'b1;
            din   = data_in;
            rd_en = 1'b0;
            @(posedge clk); // Perform write operation
            wr_en = 1'b0;   // De-assert write enable after one cycle
        end
    endtask

    task read_data_and_check;
        output [DATA_WIDTH-1:0] read_val; // For storing the DUT's dout, not for checking
        begin
            $display("INFO: Reading data at time %0t (DUT count=%0d)", $time, count);
            wr_en = 1'b0;
            rd_en = 1'b1;
            @(posedge clk); // Perform read operation; dout becomes valid
            read_val = dout; // Sample dout
            rd_en = 1'b0;   // De-assert read enable after one cycle
        end
    endtask

    task write_read_simultaneous_and_check;
        input [DATA_WIDTH-1:0] write_data;
        output [DATA_WIDTH-1:0] read_val; // For storing the DUT's dout, not for checking
        begin
            $display("INFO: Simultaneous write %h and read at time %0t (DUT count=%0d)", write_data, $time, count);
            wr_en = 1'b1;
            din   = write_data;
            rd_en = 1'b1;
            @(posedge clk); // Perform simultaneous W/R operation
            read_val = dout; // Sample dout
            wr_en = 1'b0;
            rd_en = 1'b0;
        end
    endtask


    // --------------------------------------------------------------------
    // Main Test Sequence
    // --------------------------------------------------------------------
    initial begin
        // VCD dump setup
        $dumpfile("C:/Users/91900/.gemini/antigravity/scratch/ai_verification/logs/sync_fifo.vcd");
        $dumpvars(0, tb_sync_fifo);

        // Initial testbench signal states
        clk         = 1'b0;
        rst_n       = 1'b0;
        wr_en       = 1'b0;
        rd_en       = 1'b0;
        din         = {DATA_WIDTH{1'b0}};
        error_count = 0;

        $display("INFO: Starting testbench for sync_fifo with DATA_WIDTH=%0d, DEPTH=%0d", DATA_WIDTH, DEPTH);

        // --- TEST 1: Reset Verification ---
        reset_dut;
        if (count == 0 && empty == 1 && full == 0 && overflow == 0 && underflow == 0) begin
            $display("PASS: Reset verification - FIFO is empty and flags are clear at time %0t.", $time);
        end else begin
            $display("FAIL: Reset verification - FIFO state unexpected at time %0t.", $time);
            error_count = error_count + 1;
        end

        // --- TEST 2: Fill FIFO completely ---
        $display("INFO: --- TEST 2: Fill FIFO ---");
        for (i = 0; i < DEPTH; i = i + 1) begin
            write_data_and_check({$random}); // Use $random for random data
        end
        advance_clocks(1); // Allow one extra cycle for last checks to propagate
        if (full == 1 && empty == 0 && count == DEPTH) begin
            $display("PASS: FIFO filled to capacity at time %0t.", $time);
        end else begin
            $display("FAIL: FIFO not full after %0d writes at time %0t (count=%0d).", DEPTH, $time, count);
            error_count = error_count + 1;
        end

        // --- TEST 3: Overflow check (write to full FIFO) ---
        $display("INFO: --- TEST 3: Overflow check ---");
        write_data_and_check({$random}); // Attempt to write when full
        advance_clocks(1);
        if (overflow == 1 && full == 1 && count == DEPTH) begin
            $display("PASS: Overflow detected when writing to full FIFO at time %0t.", $time);
        end else begin
            $display("FAIL: Overflow not detected or FIFO state incorrect when writing to full FIFO at time %0t (overflow=%b, count=%0d).", $time, overflow, count);
            error_count = error_count + 1;
        end

        // --- TEST 4: Empty FIFO completely ---
        $display("INFO: --- TEST 4: Empty FIFO ---");
        for (i = 0; i < DEPTH; i = i + 1) begin
            reg [DATA_WIDTH-1:0] temp_dout;
            read_data_and_check(temp_dout);
        end
        advance_clocks(1);
        if (empty == 1 && full == 0 && count == 0) begin
            $display("PASS: FIFO emptied completely at time %0t.", $time);
        end else begin
            $display("FAIL: FIFO not empty after %0d reads at time %0t (count=%0d).", DEPTH, $time, count);
            error_count = error_count + 1;
        end

        // --- TEST 5: Underflow check (read from empty FIFO) ---
        $display("INFO: --- TEST 5: Underflow check ---");
        reg [DATA_WIDTH-1:0] temp_dout;
        read_data_and_check(temp_dout); // Attempt to read when empty
        advance_clocks(1);
        if (underflow == 1 && empty == 1 && count == 0) begin
            $display("PASS: Underflow detected when reading from empty FIFO at time %0t.", $time);
        end else begin
            $display("FAIL: Underflow not detected or FIFO state incorrect when reading from empty FIFO at time %0t (underflow=%b, count=%0d).", $time, underflow, count);
            error_count = error_count + 1;
        end

        // --- TEST 6: Mixed Writes and Reads ---
        $display("INFO: --- TEST 6: Mixed Writes and Reads ---");
        reset_dut;
        for (i = 0; i < DEPTH / 2; i = i + 1) begin // Fill half
            write_data_and_check({$random});
        end
        for (i = 0; i < DEPTH / 4; i = i + 1) begin // Read a quarter
            read_data_and_check(temp_dout);
        end
        for (i = 0; i < DEPTH / 4; i = i + 1) begin // Write another quarter
            write_data_and_check({$random});
        end
        advance_clocks(1);
        if (count == DEPTH / 2 && !empty && !full) begin
             $display("PASS: Mixed write/read operations resulted in correct count (%0d) at time %0t.", count, $time);
        end else begin
             $display("FAIL: Mixed write/read operations resulted in incorrect count (%0d) at time %0t.", count, $time);
             error_count = error_count + 1;
        end

        // --- TEST 7: Simultaneous Write and Read (Partially Full) ---
        $display("INFO: --- TEST 7: Simultaneous Write/Read (Partially Full) ---");
        reset_dut;
        for (i = 0; i < DEPTH / 4; i = i + 1) begin // Fill to 1/4 full for initial state
            write_data_and_check({$random});
        end
        advance_clocks(1); // Allow state to propagate
        if (count != DEPTH / 4) begin
            $display("ERROR: Setup for TEST 7 failed. Count is %0d, expected %0d.", count, DEPTH/4);
            error_count = error_count + 1;
        end
        $display("INFO: FIFO is %0d/%0d full. Performing %0d simultaneous W/R cycles.", count, DEPTH, DEPTH/2);
        for (i = 0; i < DEPTH / 2; i = i + 1) begin // Perform several simultaneous W/R
            write_read_simultaneous_and_check({$random});
        end
        advance_clocks(1); // Final check cycle
        // Verification is handled by the always block, just check overall error_count.
        if (error_count == 0) begin
            $display("PASS: Simultaneous Write/Read (Partially Full) completed without errors at time %0t.", $time);
        end else begin
            $display("FAIL: Simultaneous Write/Read (Partially Full) reported errors at time %0t.", $time);
        end


        // --- TEST 8: Simultaneous Write and Read (When FIFO is FULL) ---
        $display("INFO: --- TEST 8: Simultaneous Write/Read (When FULL) ---");
        reset_dut;
        for (i = 0; i < DEPTH; i = i + 1) begin // Fill completely
            write_data_and_check({$random});
        end
        advance_clocks(1);
        if (!full) begin
            $display("ERROR: Setup for TEST 8 failed. FIFO not full.");
            error_count = error_count + 1;
        end
        $display("INFO: FIFO is FULL. Performing simultaneous W/R. Expecting read and overflow.");
        write_read_simultaneous_and_check({$random}); // Should read, assert overflow, count decrements
        advance_clocks(1);
        if (error_count == 0) begin
            $display("PASS: Simultaneous Write/Read (When FULL) completed without errors at time %0t.", $time);
        end else begin
            $display("FAIL: Simultaneous Write/Read (When FULL) reported errors at time %0t.", $time);
        end

        // --- TEST 9: Simultaneous Write and Read (When FIFO is EMPTY) ---
        // THIS TEST IS EXPECTED TO CATCH THE INJECTED BUG
        $display("INFO: --- TEST 9: Simultaneous Write/Read (When EMPTY) ---");
        reset_dut;
        advance_clocks(1);
        if (!empty) begin
            $display("ERROR: Setup for TEST 9 failed. FIFO not empty.");
            error_count = error_count + 1;
        end
        $display("INFO: FIFO is EMPTY. Performing simultaneous W/R. Expecting write and underflow (and DUT bug!).");
        write_read_simultaneous_and_check({$random}); // Should write, assert underflow, count increments
        advance_clocks(1);
        if (error_count > 0) begin // Expect errors here due to the bug
            $display("PASS: Simultaneous Write/Read (When EMPTY) successfully exposed the injected bug at time %0t.", $time);
        end else begin
            $display("FAIL: Simultaneous Write/Read (When EMPTY) did NOT expose the injected bug (expected errors) at time %0t.", $time);
            error_count = error_count + 1; // Mark as fail if bug isn't found
        end

        // --- TEST 10: Constrained Random Stress Test ---
        $display("INFO: --- TEST 10: Constrained Random Stress Test (100 * DEPTH cycles) ---");
        reset_dut;
        for (i = 0; i < 100 * DEPTH; i = i + 1) begin // Many random operations
            integer op_choice;
            reg [DATA_WIDTH-1:0] current_din;

            op_choice = $urandom % 3; // 0=Write, 1=Read, 2=Simultaneous W/R

            wr_en = 1'b0;
            rd_en = 1'b0;
            current_din = {$urandom}; // Always provide a random din

            case (op_choice)
                0: begin // Write
                    wr_en = 1'b1;
                    din = current_din;
                end
                1: begin // Read
                    rd_en = 1'b1;
                end
                2: begin // Simultaneous Write and Read
                    wr_en = 1'b1;
                    rd_en = 1'b1;
                    din = current_din;
                end
                default: begin // No op (should not happen with %3)
                    wr_en = 1'b0;
                    rd_en = 1'b0;
                    din = current_din;
                end
            endcase
            @(posedge clk);
        end
        wr_en = 1'b0;
        rd_en = 1'b0; // De-assert inputs
        advance_clocks(2); // Final check cycles to allow last operations to complete and be verified
        $display("INFO: Random stress test complete. Check previous messages for any errors.");


        // --- Final Report ---
        $display("INFO: Simulation finished at time %0t.", $time);
        if (error_count == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d", error_count);
        end
        $finish; // Terminate simulation
    end

endmodule