`timescale 1ns / 1ps

/**
 * Self-Checking Testbench for Parameterized Synchronous FIFO
 * Validates directed corner cases, boundary conditions, and constrained-random operations.
 */

module tb_sync_fifo();

    parameter DATA_WIDTH = 8;
    parameter DEPTH      = 16;
    parameter ADDR_WIDTH = $clog2(DEPTH);

    // DUT signals
    reg                   clk;
    reg                   rst_n;
    reg                   wr_en;
    reg  [DATA_WIDTH-1:0] din;
    reg                   rd_en;
    wire [DATA_WIDTH-1:0] dout;
    wire                  full;
    wire                  empty;
    wire                  overflow;
    wire                  underflow;
    wire [$clog2(DEPTH):0] count;

    // Testbench control & scoreboard
    integer error_count;
    integer i;

    // Shadow queue model
    reg [DATA_WIDTH-1:0] shadow_queue [0:DEPTH-1];
    integer shadow_wr_ptr;
    integer shadow_rd_ptr;
    integer shadow_count;

    // Instantiate DUT
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

    // Clock generator: 10ns period (100MHz)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Watchdog timer
    initial begin
        #5000000;
        $display("[ERROR] Watchdog timeout: simulation hung!");
        $finish;
    end

    // VCD Waveform Generation (portable relative path)
    initial begin
        $dumpfile("logs/sync_fifo.vcd");
        $dumpvars(0, tb_sync_fifo);
    end

    // Apply Reset Task
    task reset_dut;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            wr_en = 1'b0;
            rd_en = 1'b0;
            din   = {DATA_WIDTH{1'b0}};
            shadow_wr_ptr = 0;
            shadow_rd_ptr = 0;
            shadow_count  = 0;
            @(negedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);
        end
    endtask

    // Check Status Flags Task
    task check_status(input [255:0] test_name, input exp_empty, input exp_full, input [$clog2(DEPTH):0] exp_count);
        begin
            #1; // Post-clock settling
            if (empty !== exp_empty || full !== exp_full || count !== exp_count) begin
                $display("[FAIL] %0s | Expected [empty=%0b, full=%0b, count=%0d] | Got [empty=%0b, full=%0b, count=%0d]",
                         test_name, exp_empty, exp_full, exp_count, empty, full, count);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] %0s | empty=%0b, full=%0b, count=%0d", test_name, empty, full, count);
            end
        end
    endtask

    // Write Operation Task
    task write_word(input [DATA_WIDTH-1:0] data_in, input exp_overflow);
        begin
            @(negedge clk);
            wr_en = 1'b1;
            rd_en = 1'b0;
            din   = data_in;

            if (shadow_count < DEPTH) begin
                shadow_queue[shadow_wr_ptr] = data_in;
                shadow_wr_ptr = (shadow_wr_ptr == DEPTH - 1) ? 0 : shadow_wr_ptr + 1;
                shadow_count  = shadow_count + 1;
            end

            @(posedge clk);
            #1; // Sample immediately after clock edge
            wr_en = 1'b0;
            if (overflow !== exp_overflow) begin
                $display("[FAIL] Write Overflow Check | Expected: %0b, Got: %0b (din=0x%0h)", exp_overflow, overflow, data_in);
                error_count = error_count + 1;
            end
        end
    endtask

    // Read Operation Task
    task read_word(input exp_underflow);
        reg [DATA_WIDTH-1:0] exp_data;
        begin
            if (shadow_count > 0) begin
                exp_data = shadow_queue[shadow_rd_ptr];
                shadow_rd_ptr = (shadow_rd_ptr == DEPTH - 1) ? 0 : shadow_rd_ptr + 1;
                shadow_count  = shadow_count - 1;
            end else begin
                exp_data = {DATA_WIDTH{1'b0}};
            end

            @(negedge clk);
            wr_en = 1'b0;
            rd_en = 1'b1;

            @(posedge clk);
            #1;
            rd_en = 1'b0;

            if (underflow !== exp_underflow) begin
                $display("[FAIL] Read Underflow Check | Expected: %0b, Got: %0b", exp_underflow, underflow);
                error_count = error_count + 1;
            end

            if (!exp_underflow && (dout !== exp_data)) begin
                $display("[FAIL] Read Data Mismatch | Expected: 0x%0h, Got: 0x%0h", exp_data, dout);
                error_count = error_count + 1;
            end
        end
    endtask

    // Simultaneous Write and Read Task
    task simul_rw(input [DATA_WIDTH-1:0] data_in, input exp_overflow, input exp_underflow);
        reg [DATA_WIDTH-1:0] exp_data;
        begin
            // Update shadow model based on initial state before clock
            if (shadow_count == 0) begin
                // Empty: Write succeeds, read underflows
                shadow_queue[shadow_wr_ptr] = data_in;
                shadow_wr_ptr = (shadow_wr_ptr == DEPTH - 1) ? 0 : shadow_wr_ptr + 1;
                shadow_count  = shadow_count + 1;
                exp_data      = {DATA_WIDTH{1'b0}};
            end else if (shadow_count == DEPTH) begin
                // Full: Read succeeds, write overflows
                exp_data      = shadow_queue[shadow_rd_ptr];
                shadow_rd_ptr = (shadow_rd_ptr == DEPTH - 1) ? 0 : shadow_rd_ptr + 1;
                shadow_count  = shadow_count - 1;
            end else begin
                // Normal: Both succeed
                shadow_queue[shadow_wr_ptr] = data_in;
                shadow_wr_ptr = (shadow_wr_ptr == DEPTH - 1) ? 0 : shadow_wr_ptr + 1;
                exp_data      = shadow_queue[shadow_rd_ptr];
                shadow_rd_ptr = (shadow_rd_ptr == DEPTH - 1) ? 0 : shadow_rd_ptr + 1;
            end

            @(negedge clk);
            wr_en = 1'b1;
            rd_en = 1'b1;
            din   = data_in;

            @(posedge clk);
            #1;
            wr_en = 1'b0;
            rd_en = 1'b0;

            if (overflow !== exp_overflow) begin
                $display("[FAIL] Simul R/W Overflow Mismatch | Expected: %0b, Got: %0b", exp_overflow, overflow);
                error_count = error_count + 1;
            end
            if (underflow !== exp_underflow) begin
                $display("[FAIL] Simul R/W Underflow Mismatch | Expected: %0b, Got: %0b", exp_underflow, underflow);
                error_count = error_count + 1;
            end
            if (!exp_underflow && (dout !== exp_data)) begin
                $display("[FAIL] Simul R/W Data Mismatch | Expected: 0x%0h, Got: 0x%0h", exp_data, dout);
                error_count = error_count + 1;
            end
        end
    endtask

    // Main Test Procedure
    initial begin
        error_count = 0;

        $display("========================================");
        $display("   STARTING SYNC_FIFO VERIFICATION");
        $display("========================================");

        // 1. Reset Verification
        reset_dut();
        check_status("Initial Reset State", 1'b1, 1'b0, 0);

        // 2. Single Write and Single Read
        $display("\n--- Test: Single Write and Single Read ---");
        write_word(8'hA5, 1'b0);
        check_status("After 1 Write", 1'b0, 1'b0, 1);
        read_word(1'b0);
        check_status("After 1 Read", 1'b1, 1'b0, 0);

        // 3. Underflow Check
        $display("\n--- Test: Underflow Check (Read on Empty) ---");
        read_word(1'b1);
        check_status("After Underflow Read", 1'b1, 1'b0, 0);

        // 4. Fill FIFO to Capacity
        $display("\n--- Test: Fill FIFO to Capacity ---");
        for (i = 0; i < DEPTH; i = i + 1) begin
            write_word(i + 8'h10, 1'b0);
        end
        check_status("FIFO Full State", 1'b0, 1'b1, DEPTH);

        // 5. Overflow Check
        $display("\n--- Test: Overflow Check (Write on Full) ---");
        write_word(8'hFF, 1'b1);
        check_status("After Overflow Write", 1'b0, 1'b1, DEPTH);

        // 6. Read All Elements Back (Data Integrity Check)
        $display("\n--- Test: Drain FIFO & Verify Data Integrity ---");
        for (i = 0; i < DEPTH; i = i + 1) begin
            read_word(1'b0);
        end
        check_status("After Complete Drain", 1'b1, 1'b0, 0);

        // 7. Simultaneous Read & Write on Empty Boundary
        $display("\n--- Test: Simultaneous Read & Write on Empty FIFO ---");
        // Empty FIFO: write should succeed, read should underflow, count becomes 1
        simul_rw(8'h5A, 1'b0, 1'b1);
        check_status("Simul R/W on Empty", 1'b0, 1'b0, 1);

        // 8. Drain back to empty
        read_word(1'b0);
        check_status("After Drain", 1'b1, 1'b0, 0);

        // 9. Fill to DEPTH and test Simultaneous Read & Write on Full Boundary
        $display("\n--- Test: Simultaneous Read & Write on Full FIFO ---");
        for (i = 0; i < DEPTH; i = i + 1) begin
            write_word(i + 8'h20, 1'b0);
        end
        check_status("Full before Simul R/W", 1'b0, 1'b1, DEPTH);
        // Full FIFO: read should succeed, write should overflow, count becomes DEPTH-1
        simul_rw(8'h77, 1'b1, 1'b0);
        check_status("Simul R/W on Full", 1'b0, 1'b0, DEPTH - 1);

        // Drain back to empty
        for (i = 0; i < DEPTH - 1; i = i + 1) begin
            read_word(1'b0);
        end
        check_status("Drain after Full Simul", 1'b1, 1'b0, 0);

        // 10. Simultaneous Read & Write on Partially Full FIFO
        $display("\n--- Test: Simultaneous Read & Write (Partially Full) ---");
        write_word(8'h11, 1'b0);
        write_word(8'h22, 1'b0);
        check_status("Count=2 before Simul", 1'b0, 1'b0, 2);
        simul_rw(8'h33, 1'b0, 1'b0);
        check_status("Count=2 after Simul", 1'b0, 1'b0, 2);
        read_word(1'b0);
        read_word(1'b0);
        check_status("Drained to empty", 1'b1, 1'b0, 0);

        // 11. Constrained-Random Stress Testing
        $display("\n--- Test: Constrained-Random Stress Testing (500 cycles) ---");
        for (i = 0; i < 500; i = i + 1) begin
            reg [1:0] rand_op;
            reg [DATA_WIDTH-1:0] rand_val;
            rand_op  = $random & 2'b11;
            rand_val = $random & 8'hFF;

            case (rand_op)
                2'b00: begin // Idle
                    @(negedge clk);
                    wr_en = 1'b0;
                    rd_en = 1'b0;
                    @(posedge clk);
                end
                2'b01: begin // Read
                    if (shadow_count == 0)
                        read_word(1'b1); // Expect underflow
                    else
                        read_word(1'b0); // Normal read
                end
                2'b10: begin // Write
                    if (shadow_count == DEPTH)
                        write_word(rand_val, 1'b1); // Expect overflow
                    else
                        write_word(rand_val, 1'b0); // Normal write
                end
                2'b11: begin // Simultaneous Write and Read
                    if (shadow_count == 0)
                        simul_rw(rand_val, 1'b0, 1'b1); // Underflow on read
                    else if (shadow_count == DEPTH)
                        simul_rw(rand_val, 1'b1, 1'b0); // Overflow on write
                    else
                        simul_rw(rand_val, 1'b0, 1'b0); // Both succeed
                end
            endcase

            // Check invariant status flags every 10 cycles
            if (i % 10 == 0) begin
                check_status("Invariant Check", (shadow_count == 0), (shadow_count == DEPTH), shadow_count);
            end
        end
        $display("[PASS] Completed 500 random stress cycles successfully.");

        // Final Summary
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
