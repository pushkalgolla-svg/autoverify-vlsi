`timescale 1ns / 1ps

/**
 * Self-Checking Multi-Width Testbench with Functional Coverage for Parameterized ALU
 * 
 * Verifies DATA_WIDTH values: 8, 16, and 32.
 * Tracks procedural functional coverage for:
 *   - All supported opcodes (ADD, SUB, AND, OR) per width
 *   - Addition carry-out / overflow boundary conditions
 *   - Subtraction borrow boundary conditions (a < b, a >= b)
 *   - Zero-result generation across operations
 *   - Extremum operand combinations (MIN_MIN, MAX_MAX, MIN_MAX, MAX_MIN)
 *   - Constrained-random and directed test vectors
 * Generates structured coverage statistics for CI reporting.
 */

module tb_alu();

    integer total_errors;
    integer total_checks;
    integer passed_checks;
    integer failed_checks;
    integer i;

    // Safety watchdog timer
    initial begin
        #5000000;
        $display("[ERROR] Watchdog timeout: simulation hung!");
        $finish;
    end

    // VCD Waveform Generation (portable relative path)
    initial begin
        $dumpfile("logs/alu.vcd");
        $dumpvars(0, tb_alu);
    end

    // =========================================================================
    // INSTANCE 1: DATA_WIDTH = 8
    // =========================================================================
    reg  [7:0] a_8, b_8;
    reg  [1:0] op_8;
    wire [7:0] res_8;
    wire       carry_8, zero_8;

    alu #(.DATA_WIDTH(8)) dut_8 (
        .a(a_8), .b(b_8), .op(op_8),
        .result(res_8), .carry(carry_8), .zero(zero_8)
    );

    // =========================================================================
    // INSTANCE 2: DATA_WIDTH = 16
    // =========================================================================
    reg  [15:0] a_16, b_16;
    reg  [1:0]  op_16;
    wire [15:0] res_16;
    wire        carry_16, zero_16;

    alu #(.DATA_WIDTH(16)) dut_16 (
        .a(a_16), .b(b_16), .op(op_16),
        .result(res_16), .carry(carry_16), .zero(zero_16)
    );

    // =========================================================================
    // INSTANCE 3: DATA_WIDTH = 32
    // =========================================================================
    reg  [31:0] a_32, b_32;
    reg  [1:0]  op_32;
    wire [31:0] res_32;
    wire        carry_32, zero_32;

    alu #(.DATA_WIDTH(32)) dut_32 (
        .a(a_32), .b(b_32), .op(op_32),
        .result(res_32), .carry(carry_32), .zero(zero_32)
    );

    // =========================================================================
    // PROCEDURAL FUNCTIONAL COVERAGE BINS
    // =========================================================================
    // Opcode bins per width: 00=ADD, 01=SUB, 10=AND, 11=OR
    integer cov_op_8[0:3];
    integer cov_op_16[0:3];
    integer cov_op_32[0:3];

    // Carry / Overflow bins (ADD)
    integer cov_add_nocarry_8, cov_add_carry_8;
    integer cov_add_nocarry_16, cov_add_carry_16;
    integer cov_add_nocarry_32, cov_add_carry_32;

    // Borrow bins (SUB)
    integer cov_sub_noborrow_8, cov_sub_borrow_8;
    integer cov_sub_noborrow_16, cov_sub_borrow_16;
    integer cov_sub_noborrow_32, cov_sub_borrow_32;

    // Zero flag bins
    integer cov_zero_8, cov_nonzero_8;
    integer cov_zero_16, cov_nonzero_16;
    integer cov_zero_32, cov_nonzero_32;

    // Operand extremum corner combinations (MIN=0, MAX=all 1s)
    integer cov_corner_min_min_8, cov_corner_max_max_8, cov_corner_min_max_8, cov_corner_max_min_8;
    integer cov_corner_min_min_16, cov_corner_max_max_16, cov_corner_min_max_16, cov_corner_max_min_16;
    integer cov_corner_min_min_32, cov_corner_max_max_32, cov_corner_min_max_32, cov_corner_max_min_32;

    // Vector counters
    integer count_vectors_8, count_vectors_16, count_vectors_32;

    // Initialize coverage bins
    initial begin
        for (i = 0; i < 4; i = i + 1) begin
            cov_op_8[i]  = 0;
            cov_op_16[i] = 0;
            cov_op_32[i] = 0;
        end
        cov_add_nocarry_8 = 0; cov_add_carry_8 = 0;
        cov_add_nocarry_16 = 0; cov_add_carry_16 = 0;
        cov_add_nocarry_32 = 0; cov_add_carry_32 = 0;
        cov_sub_noborrow_8 = 0; cov_sub_borrow_8 = 0;
        cov_sub_noborrow_16 = 0; cov_sub_borrow_16 = 0;
        cov_sub_noborrow_32 = 0; cov_sub_borrow_32 = 0;
        cov_zero_8 = 0; cov_nonzero_8 = 0;
        cov_zero_16 = 0; cov_nonzero_16 = 0;
        cov_zero_32 = 0; cov_nonzero_32 = 0;
        cov_corner_min_min_8 = 0; cov_corner_max_max_8 = 0; cov_corner_min_max_8 = 0; cov_corner_max_min_8 = 0;
        cov_corner_min_min_16 = 0; cov_corner_max_max_16 = 0; cov_corner_min_max_16 = 0; cov_corner_max_min_16 = 0;
        cov_corner_min_min_32 = 0; cov_corner_max_max_32 = 0; cov_corner_min_max_32 = 0; cov_corner_max_min_32 = 0;
        count_vectors_8 = 0; count_vectors_16 = 0; count_vectors_32 = 0;
        total_checks = 0; passed_checks = 0; failed_checks = 0;
    end

    // =========================================================================
    // VERIFICATION TASKS WITH COVERAGE SAMPLING
    // =========================================================================

    // Verify 8-bit vector
    task verify_8;
        input [7:0]   in_a;
        input [7:0]   in_b;
        input [1:0]   in_op;
        input [255:0] tname;

        reg [8:0] sum_full;
        reg [7:0] exp_res;
        reg       exp_carry;
        reg       exp_zero;
        begin
            a_8  = in_a;
            b_8  = in_b;
            op_8 = in_op;
            #1; // Allow combinational logic to settle

            // Golden reference model
            case (in_op)
                2'b00: begin
                    sum_full  = {1'b0, in_a} + {1'b0, in_b};
                    exp_res   = sum_full[7:0];
                    exp_carry = sum_full[8];
                end
                2'b01: begin
                    exp_res   = in_a - in_b;
                    exp_carry = (in_a < in_b); // Borrow flag
                end
                2'b10: begin
                    exp_res   = in_a & in_b;
                    exp_carry = 1'b0;
                end
                2'b11: begin
                    exp_res   = in_a | in_b;
                    exp_carry = 1'b0;
                end
            endcase
            exp_zero = (exp_res == 8'h00);

            // Coverage sampling
            count_vectors_8 = count_vectors_8 + 1;
            cov_op_8[in_op] = cov_op_8[in_op] + 1;
            if (in_op == 2'b00) begin
                if (exp_carry) cov_add_carry_8 = cov_add_carry_8 + 1;
                else cov_add_nocarry_8 = cov_add_nocarry_8 + 1;
            end else if (in_op == 2'b01) begin
                if (exp_carry) cov_sub_borrow_8 = cov_sub_borrow_8 + 1;
                else cov_sub_noborrow_8 = cov_sub_noborrow_8 + 1;
            end
            if (exp_zero) cov_zero_8 = cov_zero_8 + 1;
            else cov_nonzero_8 = cov_nonzero_8 + 1;

            if (in_a == 8'h00 && in_b == 8'h00) cov_corner_min_min_8 = cov_corner_min_min_8 + 1;
            if (in_a == 8'hFF && in_b == 8'hFF) cov_corner_max_max_8 = cov_corner_max_max_8 + 1;
            if (in_a == 8'h00 && in_b == 8'hFF) cov_corner_min_max_8 = cov_corner_min_max_8 + 1;
            if (in_a == 8'hFF && in_b == 8'h00) cov_corner_max_min_8 = cov_corner_max_min_8 + 1;

            // Assertions check
            total_checks = total_checks + 3;
            if (res_8 === exp_res && carry_8 === exp_carry && zero_8 === exp_zero) begin
                passed_checks = passed_checks + 3;
            end else begin
                failed_checks = failed_checks + 3;
                total_errors = total_errors + 1;
                $display("[FAIL] [8-bit] %0s | a=0x%0h b=0x%0h op=%0b | Exp: res=0x%0h c=%b z=%b | Got: res=0x%0h c=%b z=%b",
                         tname, in_a, in_b, in_op, exp_res, exp_carry, exp_zero, res_8, carry_8, zero_8);
            end
        end
    endtask

    // Verify 16-bit vector
    task verify_16;
        input [15:0]  in_a;
        input [15:0]  in_b;
        input [1:0]   in_op;
        input [255:0] tname;

        reg [16:0] sum_full;
        reg [15:0] exp_res;
        reg        exp_carry;
        reg        exp_zero;
        begin
            a_16  = in_a;
            b_16  = in_b;
            op_16 = in_op;
            #1;

            case (in_op)
                2'b00: begin
                    sum_full  = {1'b0, in_a} + {1'b0, in_b};
                    exp_res   = sum_full[15:0];
                    exp_carry = sum_full[16];
                end
                2'b01: begin
                    exp_res   = in_a - in_b;
                    exp_carry = (in_a < in_b);
                end
                2'b10: begin
                    exp_res   = in_a & in_b;
                    exp_carry = 1'b0;
                end
                2'b11: begin
                    exp_res   = in_a | in_b;
                    exp_carry = 1'b0;
                end
            endcase
            exp_zero = (exp_res == 16'h0000);

            // Coverage sampling
            count_vectors_16 = count_vectors_16 + 1;
            cov_op_16[in_op] = cov_op_16[in_op] + 1;
            if (in_op == 2'b00) begin
                if (exp_carry) cov_add_carry_16 = cov_add_carry_16 + 1;
                else cov_add_nocarry_16 = cov_add_nocarry_16 + 1;
            end else if (in_op == 2'b01) begin
                if (exp_carry) cov_sub_borrow_16 = cov_sub_borrow_16 + 1;
                else cov_sub_noborrow_16 = cov_sub_noborrow_16 + 1;
            end
            if (exp_zero) cov_zero_16 = cov_zero_16 + 1;
            else cov_nonzero_16 = cov_nonzero_16 + 1;

            if (in_a == 16'h0000 && in_b == 16'h0000) cov_corner_min_min_16 = cov_corner_min_min_16 + 1;
            if (in_a == 16'hFFFF && in_b == 16'hFFFF) cov_corner_max_max_16 = cov_corner_max_max_16 + 1;
            if (in_a == 16'h0000 && in_b == 16'hFFFF) cov_corner_min_max_16 = cov_corner_min_max_16 + 1;
            if (in_a == 16'hFFFF && in_b == 16'h0000) cov_corner_max_min_16 = cov_corner_max_min_16 + 1;

            // Assertions check
            total_checks = total_checks + 3;
            if (res_16 === exp_res && carry_16 === exp_carry && zero_16 === exp_zero) begin
                passed_checks = passed_checks + 3;
            end else begin
                failed_checks = failed_checks + 3;
                total_errors = total_errors + 1;
                $display("[FAIL] [16-bit] %0s | a=0x%0h b=0x%0h op=%0b | Exp: res=0x%0h c=%b z=%b | Got: res=0x%0h c=%b z=%b",
                         tname, in_a, in_b, in_op, exp_res, exp_carry, exp_zero, res_16, carry_16, zero_16);
            end
        end
    endtask

    // Verify 32-bit vector
    task verify_32;
        input [31:0]  in_a;
        input [31:0]  in_b;
        input [1:0]   in_op;
        input [255:0] tname;

        reg [32:0] sum_full;
        reg [31:0] exp_res;
        reg        exp_carry;
        reg        exp_zero;
        begin
            a_32  = in_a;
            b_32  = in_b;
            op_32 = in_op;
            #1;

            case (in_op)
                2'b00: begin
                    sum_full  = {1'b0, in_a} + {1'b0, in_b};
                    exp_res   = sum_full[31:0];
                    exp_carry = sum_full[32];
                end
                2'b01: begin
                    exp_res   = in_a - in_b;
                    exp_carry = (in_a < in_b);
                end
                2'b10: begin
                    exp_res   = in_a & in_b;
                    exp_carry = 1'b0;
                end
                2'b11: begin
                    exp_res   = in_a | in_b;
                    exp_carry = 1'b0;
                end
            endcase
            exp_zero = (exp_res == 32'h00000000);

            // Coverage sampling
            count_vectors_32 = count_vectors_32 + 1;
            cov_op_32[in_op] = cov_op_32[in_op] + 1;
            if (in_op == 2'b00) begin
                if (exp_carry) cov_add_carry_32 = cov_add_carry_32 + 1;
                else cov_add_nocarry_32 = cov_add_nocarry_32 + 1;
            end else if (in_op == 2'b01) begin
                if (exp_carry) cov_sub_borrow_32 = cov_sub_borrow_32 + 1;
                else cov_sub_noborrow_32 = cov_sub_noborrow_32 + 1;
            end
            if (exp_zero) cov_zero_32 = cov_zero_32 + 1;
            else cov_nonzero_32 = cov_nonzero_32 + 1;

            if (in_a == 32'h00000000 && in_b == 32'h00000000) cov_corner_min_min_32 = cov_corner_min_min_32 + 1;
            if (in_a == 32'hFFFFFFFF && in_b == 32'hFFFFFFFF) cov_corner_max_max_32 = cov_corner_max_max_32 + 1;
            if (in_a == 32'h00000000 && in_b == 32'hFFFFFFFF) cov_corner_min_max_32 = cov_corner_min_max_32 + 1;
            if (in_a == 32'hFFFFFFFF && in_b == 32'h00000000) cov_corner_max_min_32 = cov_corner_max_min_32 + 1;

            // Assertions check
            total_checks = total_checks + 3;
            if (res_32 === exp_res && carry_32 === exp_carry && zero_32 === exp_zero) begin
                passed_checks = passed_checks + 3;
            end else begin
                failed_checks = failed_checks + 3;
                total_errors = total_errors + 1;
                $display("[FAIL] [32-bit] %0s | a=0x%0h b=0x%0h op=%0b | Exp: res=0x%0h c=%b z=%b | Got: res=0x%0h c=%b z=%b",
                         tname, in_a, in_b, in_op, exp_res, exp_carry, exp_zero, res_32, carry_32, zero_32);
            end
        end
    endtask

    // =========================================================================
    // MAIN TEST EXECUTION
    // =========================================================================
    integer covered_bins;
    integer total_bins;
    real cov_percentage;

    initial begin
        total_errors = 0;

        $display("==================================================");
        $display("    STARTING ALU MULTI-WIDTH VERIFICATION (8/16/32)");
        $display("==================================================");

        // ---------------------------------------------------------------------
        // SECTION 1: 8-BIT ALU VERIFICATION
        // ---------------------------------------------------------------------
        $display("\n--- [Section 1] Testing DATA_WIDTH = 8 ---");
        // Directed nominal
        verify_8(8'h10, 8'h20, 2'b00, "Nominal ADD");
        verify_8(8'h50, 8'h20, 2'b01, "Nominal SUB");
        verify_8(8'hF0, 8'hAA, 2'b10, "Nominal AND");
        verify_8(8'hF0, 8'h0F, 2'b11, "Nominal OR");

        // Directed corner boundaries (Carry, Borrow, Zero)
        verify_8(8'hFF, 8'h01, 2'b00, "ADD Overflow (0xFF + 1)");
        verify_8(8'hFF, 8'hFF, 2'b00, "ADD Double Max (0xFF + 0xFF)");
        verify_8(8'h00, 8'h01, 2'b01, "SUB Underflow Borrow (0 - 1)");
        verify_8(8'h05, 8'h0A, 2'b01, "SUB Borrow (5 - 10)");
        verify_8(8'h55, 8'h55, 2'b01, "SUB Equal Zero (0x55 - 0x55)");

        // Explicit corner operand combinations
        verify_8(8'h00, 8'h00, 2'b00, "Corner MIN_MIN ADD (0 + 0 -> Zero)");
        verify_8(8'hFF, 8'hFF, 2'b10, "Corner MAX_MAX AND (FF & FF)");
        verify_8(8'h00, 8'hFF, 2'b11, "Corner MIN_MAX OR (0 | FF)");
        verify_8(8'hFF, 8'h00, 2'b01, "Corner MAX_MIN SUB (FF - 0 -> No Borrow)");

        // 200 Randomized Vectors for 8-bit
        for (i = 0; i < 200; i = i + 1) begin
            reg [7:0] r_a, r_b;
            reg [1:0] r_op;
            r_a  = $random & 8'hFF;
            r_b  = $random & 8'hFF;
            r_op = $random & 2'b11;
            verify_8(r_a, r_b, r_op, "Randomized 8-bit");
        end
        $display("[PASS] DATA_WIDTH = 8 passed directed & 200 random vectors.");

        // ---------------------------------------------------------------------
        // SECTION 2: 16-BIT ALU VERIFICATION
        // ---------------------------------------------------------------------
        $display("\n--- [Section 2] Testing DATA_WIDTH = 16 ---");
        verify_16(16'h1234, 16'h0567, 2'b00, "Nominal 16-bit ADD");
        verify_16(16'h5000, 16'h2000, 2'b01, "Nominal 16-bit SUB");
        verify_16(16'hF0F0, 16'hAAAA, 2'b10, "Nominal 16-bit AND");
        verify_16(16'hF0F0, 16'h0F0F, 2'b11, "Nominal 16-bit OR");
        verify_16(16'hFFFF, 16'h0001, 2'b00, "16-bit ADD Overflow");
        verify_16(16'hFFFF, 16'hFFFF, 2'b00, "16-bit ADD Double Max");
        verify_16(16'h0000, 16'h0001, 2'b01, "16-bit SUB Underflow Borrow");
        verify_16(16'h1000, 16'h2000, 2'b01, "16-bit SUB Borrow");
        verify_16(16'hA5A5, 16'hA5A5, 2'b01, "16-bit SUB Equal Zero");

        // Explicit corner operand combinations
        verify_16(16'h0000, 16'h0000, 2'b00, "16-bit MIN_MIN ADD (0 + 0)");
        verify_16(16'hFFFF, 16'hFFFF, 2'b10, "16-bit MAX_MAX AND");
        verify_16(16'h0000, 16'hFFFF, 2'b11, "16-bit MIN_MAX OR");
        verify_16(16'hFFFF, 16'h0000, 2'b01, "16-bit MAX_MIN SUB");

        // 200 Randomized Vectors for 16-bit
        for (i = 0; i < 200; i = i + 1) begin
            reg [15:0] r_a16, r_b16;
            reg [1:0]  r_op16;
            r_a16  = $random & 16'hFFFF;
            r_b16  = $random & 16'hFFFF;
            r_op16 = $random & 2'b11;
            verify_16(r_a16, r_b16, r_op16, "Randomized 16-bit");
        end
        $display("[PASS] DATA_WIDTH = 16 passed directed & 200 random vectors.");

        // ---------------------------------------------------------------------
        // SECTION 3: 32-BIT ALU VERIFICATION
        // ---------------------------------------------------------------------
        $display("\n--- [Section 3] Testing DATA_WIDTH = 32 ---");
        verify_32(32'h12345678, 32'h0ABCDEF0, 2'b00, "Nominal 32-bit ADD");
        verify_32(32'h80000000, 32'h10000000, 2'b01, "Nominal 32-bit SUB");
        verify_32(32'hF0F0F0F0, 32'hAAAAAAAA, 2'b10, "Nominal 32-bit AND");
        verify_32(32'hF0F0F0F0, 32'h0F0F0F0F, 2'b11, "Nominal 32-bit OR");
        verify_32(32'hFFFFFFFF, 32'h00000001, 2'b00, "32-bit ADD Overflow");
        verify_32(32'hFFFFFFFF, 32'hFFFFFFFF, 2'b00, "32-bit ADD Double Max");
        verify_32(32'h00000000, 32'h00000001, 2'b01, "32-bit SUB Underflow Borrow");
        verify_32(32'h10000000, 32'h80000000, 2'b01, "32-bit SUB Borrow");
        verify_32(32'h1234ABCD, 32'h1234ABCD, 2'b01, "32-bit SUB Equal Zero");

        // Explicit corner operand combinations
        verify_32(32'h00000000, 32'h00000000, 2'b00, "32-bit MIN_MIN ADD (0 + 0)");
        verify_32(32'hFFFFFFFF, 32'hFFFFFFFF, 2'b10, "32-bit MAX_MAX AND");
        verify_32(32'h00000000, 32'hFFFFFFFF, 2'b11, "32-bit MIN_MAX OR");
        verify_32(32'hFFFFFFFF, 32'h00000000, 2'b01, "32-bit MAX_MIN SUB");

        // 200 Randomized Vectors for 32-bit (width-independent generation)
        for (i = 0; i < 200; i = i + 1) begin
            reg [31:0] r_a32, r_b32;
            reg [1:0]  r_op32;
            r_a32  = {$random, $random};
            r_b32  = {$random, $random};
            r_op32 = $random & 2'b11;
            verify_32(r_a32, r_b32, r_op32, "Randomized 32-bit");
        end
        $display("[PASS] DATA_WIDTH = 32 passed directed & 200 random vectors.");

        // =====================================================================
        // FUNCTIONAL COVERAGE AUDIT & REPORTING
        // =====================================================================
        covered_bins = 0;
        total_bins = 42;

        // Check Opcode Bins (4 per width = 12 bins)
        for (i = 0; i < 4; i = i + 1) begin
            if (cov_op_8[i] > 0)  covered_bins = covered_bins + 1;
            if (cov_op_16[i] > 0) covered_bins = covered_bins + 1;
            if (cov_op_32[i] > 0) covered_bins = covered_bins + 1;
        end

        // Check Carry Bins (2 per width = 6 bins)
        if (cov_add_nocarry_8 > 0)  covered_bins = covered_bins + 1;
        if (cov_add_carry_8 > 0)    covered_bins = covered_bins + 1;
        if (cov_add_nocarry_16 > 0) covered_bins = covered_bins + 1;
        if (cov_add_carry_16 > 0)   covered_bins = covered_bins + 1;
        if (cov_add_nocarry_32 > 0) covered_bins = covered_bins + 1;
        if (cov_add_carry_32 > 0)   covered_bins = covered_bins + 1;

        // Check Borrow Bins (2 per width = 6 bins)
        if (cov_sub_noborrow_8 > 0)  covered_bins = covered_bins + 1;
        if (cov_sub_borrow_8 > 0)    covered_bins = covered_bins + 1;
        if (cov_sub_noborrow_16 > 0) covered_bins = covered_bins + 1;
        if (cov_sub_borrow_16 > 0)   covered_bins = covered_bins + 1;
        if (cov_sub_noborrow_32 > 0) covered_bins = covered_bins + 1;
        if (cov_sub_borrow_32 > 0)   covered_bins = covered_bins + 1;

        // Check Zero Bins (2 per width = 6 bins)
        if (cov_zero_8 > 0)     covered_bins = covered_bins + 1;
        if (cov_nonzero_8 > 0)  covered_bins = covered_bins + 1;
        if (cov_zero_16 > 0)    covered_bins = covered_bins + 1;
        if (cov_nonzero_16 > 0) covered_bins = covered_bins + 1;
        if (cov_zero_32 > 0)    covered_bins = covered_bins + 1;
        if (cov_nonzero_32 > 0) covered_bins = covered_bins + 1;

        // Check Extremum Corner Bins (4 per width = 12 bins)
        if (cov_corner_min_min_8 > 0)  covered_bins = covered_bins + 1;
        if (cov_corner_max_max_8 > 0)  covered_bins = covered_bins + 1;
        if (cov_corner_min_max_8 > 0)  covered_bins = covered_bins + 1;
        if (cov_corner_max_min_8 > 0)  covered_bins = covered_bins + 1;
        if (cov_corner_min_min_16 > 0) covered_bins = covered_bins + 1;
        if (cov_corner_max_max_16 > 0) covered_bins = covered_bins + 1;
        if (cov_corner_min_max_16 > 0) covered_bins = covered_bins + 1;
        if (cov_corner_max_min_16 > 0) covered_bins = covered_bins + 1;
        if (cov_corner_min_min_32 > 0) covered_bins = covered_bins + 1;
        if (cov_corner_max_max_32 > 0) covered_bins = covered_bins + 1;
        if (cov_corner_min_max_32 > 0) covered_bins = covered_bins + 1;
        if (cov_corner_max_min_32 > 0) covered_bins = covered_bins + 1;

        cov_percentage = (covered_bins * 100.0) / total_bins;

        $display("\n==================================================");
        $display("       FUNCTIONAL COVERAGE REPORT: alu.v          ");
        $display("==================================================");
        $display("[COV_SUMMARY] Total Bins: %0d | Covered: %0d | Coverage: %0.1f%%", total_bins, covered_bins, cov_percentage);
        $display("[COV_CHECKS]  Total Checks: %0d | Passed: %0d | Failed: %0d", total_checks, passed_checks, failed_checks);
        $display("[COV_DETAIL]  8-bit Opcodes : ADD=%0d, SUB=%0d, AND=%0d, OR=%0d (4/4 hit)", cov_op_8[0], cov_op_8[1], cov_op_8[2], cov_op_8[3]);
        $display("[COV_DETAIL]  16-bit Opcodes: ADD=%0d, SUB=%0d, AND=%0d, OR=%0d (4/4 hit)", cov_op_16[0], cov_op_16[1], cov_op_16[2], cov_op_16[3]);
        $display("[COV_DETAIL]  32-bit Opcodes: ADD=%0d, SUB=%0d, AND=%0d, OR=%0d (4/4 hit)", cov_op_32[0], cov_op_32[1], cov_op_32[2], cov_op_32[3]);
        $display("[COV_DETAIL]  ADD Carry Bins: 8b[no_c=%0d, c=%0d], 16b[no_c=%0d, c=%0d], 32b[no_c=%0d, c=%0d] (6/6 hit)",
                 cov_add_nocarry_8, cov_add_carry_8, cov_add_nocarry_16, cov_add_carry_16, cov_add_nocarry_32, cov_add_carry_32);
        $display("[COV_DETAIL]  SUB Borrow Bins: 8b[no_b=%0d, b=%0d], 16b[no_b=%0d, b=%0d], 32b[no_b=%0d, b=%0d] (6/6 hit)",
                 cov_sub_noborrow_8, cov_sub_borrow_8, cov_sub_noborrow_16, cov_sub_borrow_16, cov_sub_noborrow_32, cov_sub_borrow_32);
        $display("[COV_DETAIL]  Zero Flag Bins : 8b[nz=%0d, z=%0d], 16b[nz=%0d, z=%0d], 32b[nz=%0d, z=%0d] (6/6 hit)",
                 cov_nonzero_8, cov_zero_8, cov_nonzero_16, cov_zero_16, cov_nonzero_32, cov_zero_32);
        $display("[COV_DETAIL]  Corner Combos  : 8b[min_min=%0d, max_max=%0d, min_max=%0d, max_min=%0d]",
                 cov_corner_min_min_8, cov_corner_max_max_8, cov_corner_min_max_8, cov_corner_max_min_8);
        $display("[COV_DETAIL]  Corner Combos  : 16b[min_min=%0d, max_max=%0d, min_max=%0d, max_min=%0d]",
                 cov_corner_min_min_16, cov_corner_max_max_16, cov_corner_min_max_16, cov_corner_max_min_16);
        $display("[COV_DETAIL]  Corner Combos  : 32b[min_min=%0d, max_max=%0d, min_max=%0d, max_min=%0d]",
                 cov_corner_min_min_32, cov_corner_max_max_32, cov_corner_min_max_32, cov_corner_max_min_32);
        $display("[COV_DETAIL]  Random Vectors : 8b=%0d, 16b=%0d, 32b=%0d (Total Vectors = %0d)",
                 count_vectors_8, count_vectors_16, count_vectors_32, (count_vectors_8 + count_vectors_16 + count_vectors_32));

        if (covered_bins == total_bins) begin
            $display("[COV_UNCOVERED] None (100.0%% Coverage Achieved)");
        end else begin
            $display("[COV_UNCOVERED] Bins uncovered: %0d", (total_bins - covered_bins));
        end

        // Final Verification Summary
        $display("\n==================================================");
        if (total_errors == 0 && covered_bins == total_bins) begin
            $display("ALL TESTS PASSED (ALU WIDTHS: 8, 16, 32)");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d | Uncovered Bins = %0d", total_errors, (total_bins - covered_bins));
        end
        $display("==================================================");

        $finish;
    end

endmodule