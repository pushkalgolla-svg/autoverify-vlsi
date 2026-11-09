`timescale 1ns / 1ps

/**
 * Self-Checking Testbench for Parameterized Synchronous FIFO
 * Validates:
 *   1. Full-capacity FIFO (DEPTH = 16): Directed nominal, boundaries, simultaneous R/W, 500 random cycles.
 *   2. Non-power-of-two FIFO (DEPTH = 5): Pointer wrap-around, boundary collision, arbitrary depth.
 *   3. Single-word FIFO (DEPTH = 1): Edge-case minimal depth safety, empty/full single-cycle toggling.
 */

module tb_sync_fifo();

    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst_n;
    integer total_errors;

    // Clock generator: 100MHz (10ns)
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Safety Watchdog Timer
    initial begin
        #10000000;
        $display("[ERROR] Watchdog timeout: simulation hung!");
        $finish;
    end

    // Waveform dumping (relative path)
    initial begin
        $dumpfile("logs/sync_fifo.vcd");
        $dumpvars(0, tb_sync_fifo);
    end

    // =========================================================================
    // INSTANCE 1: Standard DEPTH = 16
    // =========================================================================
    reg                   wr_en_16;
    reg  [DATA_WIDTH-1:0] din_16;
    reg                   rd_en_16;
    wire [DATA_WIDTH-1:0] dout_16;
    wire                  full_16;
    wire                  empty_16;
    wire                  overflow_16;
    wire                  underflow_16;
    wire [4:0]            count_16;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(16)
    ) dut_16 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en_16),
        .din(din_16),
        .rd_en(rd_en_16),
        .dout(dout_16),
        .full(full_16),
        .empty(empty_16),
        .overflow(overflow_16),
        .underflow(underflow_16),
        .count(count_16)
    );

    // =========================================================================
    // INSTANCE 2: Non-power-of-two DEPTH = 5
    // =========================================================================
    reg                   wr_en_5;
    reg  [DATA_WIDTH-1:0] din_5;
    reg                   rd_en_5;
    wire [DATA_WIDTH-1:0] dout_5;
    wire                  full_5;
    wire                  empty_5;
    wire                  overflow_5;
    wire                  underflow_5;
    wire [3:0]            count_5;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(5)
    ) dut_5 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en_5),
        .din(din_5),
        .rd_en(rd_en_5),
        .dout(dout_5),
        .full(full_5),
        .empty(empty_5),
        .overflow(overflow_5),
        .underflow(underflow_5),
        .count(count_5)
    );

    // =========================================================================
    // INSTANCE 3: Minimal Single-Word DEPTH = 1
    // =========================================================================
    reg                   wr_en_1;
    reg  [DATA_WIDTH-1:0] din_1;
    reg                   rd_en_1;
    wire [DATA_WIDTH-1:0] dout_1;
    wire                  full_1;
    wire                  empty_1;
    wire                  overflow_1;
    wire                  underflow_1;
    wire [1:0]            count_1;

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(1)
    ) dut_1 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en_1),
        .din(din_1),
        .rd_en(rd_en_1),
        .dout(dout_1),
        .full(full_1),
        .empty(empty_1),
        .overflow(overflow_1),
        .underflow(underflow_1),
        .count(count_1)
    );

    // Shadow queue for DEPTH=16 random testing
    reg [DATA_WIDTH-1:0] shadow_queue_16 [0:15];
    integer shadow_wr_ptr_16;
    integer shadow_rd_ptr_16;
    integer shadow_count_16;

    // Reset task
    task apply_reset;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            wr_en_16 = 0; din_16 = 0; rd_en_16 = 0;
            wr_en_5  = 0; din_5  = 0; rd_en_5  = 0;
            wr_en_1  = 0; din_1  = 0; rd_en_1  = 0;
            shadow_wr_ptr_16 = 0;
            shadow_rd_ptr_16 = 0;
            shadow_count_16  = 0;
            #(CLK_PERIOD * 3);
            @(negedge clk);
            rst_n = 1'b1;
            #(CLK_PERIOD * 2);
        end
    endtask

    // Check macros/helpers
    task check_condition;
        input condition;
        input [511:0] msg;
        begin
            if (!condition) begin
                $display("[FAIL] %0s", msg);
                total_errors = total_errors + 1;
            end
        end
    endtask

    // Main Test Sequence
    integer i;
    initial begin
        total_errors = 0;

        $display("==================================================");
        $display("    STARTING SYNC_FIFO MULTI-DEPTH VERIFICATION   ");
        $display("==================================================");

        apply_reset();

        // ---------------------------------------------------------------------
        // SECTION 1: VERIFY DEPTH = 1 (Minimal Single-Word FIFO)
        // ---------------------------------------------------------------------
        $display("\n--- [Section 1] Testing Minimal Single-Word FIFO (DEPTH = 1) ---");
        check_condition(empty_1 === 1'b1 && full_1 === 1'b0 && count_1 === 2'd0,
                        "DEPTH=1: Initial state must be empty=1, full=0, count=0");

        // 1.1 Underflow on empty
        @(negedge clk);
        rd_en_1 = 1'b1;
        @(negedge clk);
        rd_en_1 = 1'b0;
        check_condition(underflow_1 === 1'b1 && empty_1 === 1'b1 && count_1 === 2'd0,
                        "DEPTH=1: Read on empty must assert underflow and keep count=0");

        // 1.2 Write single item -> must become full immediately
        @(negedge clk);
        wr_en_1 = 1'b1;
        din_1   = 8'hA1;
        @(negedge clk);
        wr_en_1 = 1'b0;
        check_condition(empty_1 === 1'b0 && full_1 === 1'b1 && count_1 === 2'd1,
                        "DEPTH=1: After single write, FIFO must be empty=0, full=1, count=1");

        // 1.3 Overflow on full
        @(negedge clk);
        wr_en_1 = 1'b1;
        din_1   = 8'hB2;
        @(negedge clk);
        wr_en_1 = 1'b0;
        check_condition(overflow_1 === 1'b1 && full_1 === 1'b1 && count_1 === 2'd1,
                        "DEPTH=1: Write on full must assert overflow and keep count=1");

        // 1.4 Simultaneous R/W on full FIFO: Read succeeds, write fails (overflow), count becomes 0
        @(negedge clk);
        wr_en_1 = 1'b1; din_1 = 8'hC3;
        rd_en_1 = 1'b1;
        @(negedge clk);
        wr_en_1 = 1'b0;
        rd_en_1 = 1'b0;
        check_condition(dout_1 === 8'hA1, "DEPTH=1: Simultaneous R/W on full must output old word (0xA1)");
        check_condition(overflow_1 === 1'b1 && empty_1 === 1'b1 && count_1 === 2'd0,
                        "DEPTH=1: Simultaneous R/W on full must flag overflow and empty FIFO (count=0)");

        // 1.5 Simultaneous R/W on empty FIFO: Write succeeds, read fails (underflow), count becomes 1
        @(negedge clk);
        wr_en_1 = 1'b1; din_1 = 8'hD4;
        rd_en_1 = 1'b1;
        @(negedge clk);
        wr_en_1 = 1'b0;
        rd_en_1 = 1'b0;
        check_condition(underflow_1 === 1'b1 && full_1 === 1'b1 && count_1 === 2'd1,
                        "DEPTH=1: Simultaneous R/W on empty must flag underflow and fill FIFO (count=1)");

        // 1.6 Read out the written item
        @(negedge clk);
        rd_en_1 = 1'b1;
        @(negedge clk);
        rd_en_1 = 1'b0;
        check_condition(dout_1 === 8'hD4 && empty_1 === 1'b1 && count_1 === 2'd0,
                        "DEPTH=1: Final read must return 0xD4 and leave FIFO empty");
        $display("[PASS] DEPTH=1 verification completed successfully.");

        // ---------------------------------------------------------------------
        // SECTION 2: VERIFY DEPTH = 5 (Arbitrary Non-Power-of-Two FIFO)
        // ---------------------------------------------------------------------
        $display("\n--- [Section 2] Testing Non-Power-of-Two FIFO (DEPTH = 5) ---");
        check_condition(empty_5 === 1'b1 && full_5 === 1'b0 && count_5 === 4'd0,
                        "DEPTH=5: Initial state must be empty=1, full=0, count=0");

        // 2.1 Fill exactly 5 elements
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk);
            wr_en_5 = 1'b1;
            din_5   = 8'h10 + i;
            @(negedge clk);
            wr_en_5 = 1'b0;
            check_condition(count_5 === (i + 1), "DEPTH=5: Count increment check during fill");
        end
        check_condition(full_5 === 1'b1 && empty_5 === 1'b0 && count_5 === 4'd5,
                        "DEPTH=5: Full flag asserted when filled to 5");

        // 2.2 Attempt write on full (overflow)
        @(negedge clk);
        wr_en_5 = 1'b1; din_5 = 8'hEE;
        @(negedge clk);
        wr_en_5 = 1'b0;
        check_condition(overflow_5 === 1'b1 && count_5 === 4'd5,
                        "DEPTH=5: Overflow asserted on 6th write attempt");

        // 2.3 Drain 5 elements & verify sequential pointer wrap (0->1->2->3->4)
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk);
            rd_en_5 = 1'b1;
            @(negedge clk);
            rd_en_5 = 1'b0;
            check_condition(dout_5 === (8'h10 + i), "DEPTH=5: Data order integrity check on drain");
        end
        check_condition(empty_5 === 1'b1 && full_5 === 1'b0 && count_5 === 4'd0,
                        "DEPTH=5: FIFO empty after draining 5 items");

        // 2.4 Test multi-cycle circular pointer wrap across modulo 5 boundary
        // Push 3, Pop 3, Push 4, Pop 4...
        for (i = 0; i < 3; i = i + 1) begin
            @(negedge clk); wr_en_5 = 1'b1; din_5 = 8'h20 + i;
            @(negedge clk); wr_en_5 = 1'b0;
        end
        for (i = 0; i < 3; i = i + 1) begin
            @(negedge clk); rd_en_5 = 1'b1;
            @(negedge clk); rd_en_5 = 1'b0;
            check_condition(dout_5 === (8'h20 + i), "DEPTH=5: Wrap phase 1 data check");
        end
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk); wr_en_5 = 1'b1; din_5 = 8'h30 + i;
            @(negedge clk); wr_en_5 = 1'b0;
        end
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk); rd_en_5 = 1'b1;
            @(negedge clk); rd_en_5 = 1'b0;
            check_condition(dout_5 === (8'h30 + i), "DEPTH=5: Wrap phase 2 data check");
        end
        check_condition(empty_5 === 1'b1 && count_5 === 4'd0, "DEPTH=5: Clean empty after pointer wrap");
        $display("[PASS] DEPTH=5 verification completed successfully.");

        // ---------------------------------------------------------------------
        // SECTION 3: VERIFY DEPTH = 16 (Standard Deep FIFO)
        // ---------------------------------------------------------------------
        $display("\n--- [Section 3] Testing Standard Deep FIFO (DEPTH = 16) ---");
        check_condition(empty_16 === 1'b1 && full_16 === 1'b0 && count_16 === 5'd0,
                        "DEPTH=16: Initial state empty check");

        // 3.1 Single write & single read
        @(negedge clk); wr_en_16 = 1'b1; din_16 = 8'h5A;
        @(negedge clk); wr_en_16 = 1'b0;
        check_condition(count_16 === 5'd1 && empty_16 === 1'b0, "DEPTH=16: Count=1 after 1 write");

        @(negedge clk); rd_en_16 = 1'b1;
        @(negedge clk); rd_en_16 = 1'b0;
        check_condition(dout_16 === 8'h5A && empty_16 === 1'b1 && count_16 === 5'd0,
                        "DEPTH=16: Data read back matches and FIFO empty");

        // 3.2 Underflow check
        @(negedge clk); rd_en_16 = 1'b1;
        @(negedge clk); rd_en_16 = 1'b0;
        check_condition(underflow_16 === 1'b1 && empty_16 === 1'b1, "DEPTH=16: Underflow flag asserted");

        // 3.3 Fill to 16
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk); wr_en_16 = 1'b1; din_16 = 8'hA0 + i;
            @(negedge clk); wr_en_16 = 1'b0;
        end
        check_condition(full_16 === 1'b1 && count_16 === 5'd16, "DEPTH=16: Full flag asserted at count=16");

        // 3.4 Overflow check
        @(negedge clk); wr_en_16 = 1'b1; din_16 = 8'hFF;
        @(negedge clk); wr_en_16 = 1'b0;
        check_condition(overflow_16 === 1'b1 && count_16 === 5'd16, "DEPTH=16: Overflow flag asserted");

        // 3.5 Drain and verify 16 items
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk); rd_en_16 = 1'b1;
            @(negedge clk); rd_en_16 = 1'b0;
            check_condition(dout_16 === (8'hA0 + i), "DEPTH=16: Full drain data order check");
        end
        check_condition(empty_16 === 1'b1 && count_16 === 5'd0, "DEPTH=16: Empty after drain");

        // 3.6 Simultaneous R/W on empty FIFO
        @(negedge clk); wr_en_16 = 1'b1; din_16 = 8'h77; rd_en_16 = 1'b1;
        @(negedge clk); wr_en_16 = 1'b0; rd_en_16 = 1'b0;
        check_condition(underflow_16 === 1'b1 && count_16 === 5'd1, "DEPTH=16: Empty simul R/W check");

        @(negedge clk); rd_en_16 = 1'b1;
        @(negedge clk); rd_en_16 = 1'b0;
        check_condition(dout_16 === 8'h77 && empty_16 === 1'b1, "DEPTH=16: Drain after empty simul");

        // 3.7 Simultaneous R/W on full FIFO
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk); wr_en_16 = 1'b1; din_16 = 8'h80 + i;
            @(negedge clk); wr_en_16 = 1'b0;
        end
        @(negedge clk); wr_en_16 = 1'b1; din_16 = 8'hFE; rd_en_16 = 1'b1;
        @(negedge clk); wr_en_16 = 1'b0; rd_en_16 = 1'b0;
        check_condition(dout_16 === 8'h80, "DEPTH=16: First element read on full simul");
        check_condition(overflow_16 === 1'b1 && count_16 === 5'd15, "DEPTH=16: Overflow flag and count=15 on full simul");

        // Drain remaining 15
        for (i = 1; i < 16; i = i + 1) begin
            @(negedge clk); rd_en_16 = 1'b1;
            @(negedge clk); rd_en_16 = 1'b0;
            check_condition(dout_16 === (8'h80 + i), "DEPTH=16: Drain remaining after full simul");
        end
        check_condition(empty_16 === 1'b1 && count_16 === 5'd0, "DEPTH=16: Empty after full simul drain");

        // 3.8 Constrained-Random Stress Testing (500 cycles)
        $display("\n--- [Section 3.8] Running 500 Constrained-Random Cycles (DEPTH=16) ---");
        shadow_wr_ptr_16 = 0;
        shadow_rd_ptr_16 = 0;
        shadow_count_16  = 0;

        for (i = 0; i < 500; i = i + 1) begin
            reg rand_wr;
            reg rand_rd;
            reg [7:0] rand_val;

            rand_wr  = $random & 1'b1;
            rand_rd  = $random & 1'b1;
            rand_val = $random & 8'hFF;

            @(negedge clk);
            wr_en_16 = rand_wr;
            din_16   = rand_val;
            rd_en_16 = rand_rd;

            // Update golden shadow model
            case ({rand_wr, rand_rd})
                2'b10: begin
                    if (shadow_count_16 < 16) begin
                        shadow_queue_16[shadow_wr_ptr_16] = rand_val;
                        shadow_wr_ptr_16 = (shadow_wr_ptr_16 + 1) % 16;
                        shadow_count_16  = shadow_count_16 + 1;
                    end
                end
                2'b01: begin
                    if (shadow_count_16 > 0) begin
                        shadow_rd_ptr_16 = (shadow_rd_ptr_16 + 1) % 16;
                        shadow_count_16  = shadow_count_16 - 1;
                    end
                end
                2'b11: begin
                    if (shadow_count_16 == 0) begin
                        shadow_queue_16[shadow_wr_ptr_16] = rand_val;
                        shadow_wr_ptr_16 = (shadow_wr_ptr_16 + 1) % 16;
                        shadow_count_16  = 1;
                    end else if (shadow_count_16 == 16) begin
                        shadow_rd_ptr_16 = (shadow_rd_ptr_16 + 1) % 16;
                        shadow_count_16  = 15;
                    end else begin
                        shadow_queue_16[shadow_wr_ptr_16] = rand_val;
                        shadow_wr_ptr_16 = (shadow_wr_ptr_16 + 1) % 16;
                        shadow_rd_ptr_16 = (shadow_rd_ptr_16 + 1) % 16;
                    end
                end
                default: ;
            endcase

            @(negedge clk);
            wr_en_16 = 1'b0;
            rd_en_16 = 1'b0;

            // Check model invariant
            if (count_16 !== shadow_count_16) begin
                $display("[FAIL] Random cycle %0d count mismatch: DUT=%0d, Golden=%0d", i, count_16, shadow_count_16);
                total_errors = total_errors + 1;
            end
            if (empty_16 !== (shadow_count_16 == 0)) begin
                $display("[FAIL] Random cycle %0d empty flag mismatch: DUT=%b, Golden=%b", i, empty_16, (shadow_count_16 == 0));
                total_errors = total_errors + 1;
            end
            if (full_16 !== (shadow_count_16 == 16)) begin
                $display("[FAIL] Random cycle %0d full flag mismatch: DUT=%b, Golden=%b", i, full_16, (shadow_count_16 == 16));
                total_errors = total_errors + 1;
            end
        end

        // Drain any remaining items from random run
        while (shadow_count_16 > 0) begin
            reg [7:0] exp_val;
            exp_val = shadow_queue_16[shadow_rd_ptr_16];
            shadow_rd_ptr_16 = (shadow_rd_ptr_16 + 1) % 16;
            shadow_count_16 = shadow_count_16 - 1;

            @(negedge clk);
            rd_en_16 = 1'b1;
            @(negedge clk);
            rd_en_16 = 1'b0;
            if (dout_16 !== exp_val) begin
                $display("[FAIL] Post-random drain data mismatch: Expected 0x%0h, Got 0x%0h", exp_val, dout_16);
                total_errors = total_errors + 1;
            end
        end
        $display("[PASS] Completed 500 random stress cycles (DEPTH=16).");

        // Final Summary
        $display("\n==================================================");
        if (total_errors == 0) begin
            $display("ALL TESTS PASSED (DEPTH=1, DEPTH=5, DEPTH=16)");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d", total_errors);
        end
        $display("==================================================");

        $finish;
    end

endmodule
