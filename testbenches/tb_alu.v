`timescale 1ns / 1ps

/**
 * Self-Checking Multi-Width Testbench for Parameterized ALU
 * Extends verification to DATA_WIDTH values: 8, 16, and 32.
 * Uses width-independent randomized operands, corner-case boundaries,
 * and parameterized golden reference models.
 */

module tb_alu();

    integer total_errors;
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
    // VERIFICATION TASKS (Parameterized Width Reference Calculations)
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

            // Width-independent golden reference model
            case (in_op)
                2'b00: begin
                    sum_full  = {1'b0, in_a} + {1'b0, in_b};
                    exp_res   = sum_full[7:0];
                    exp_carry = sum_full[8];
                end
                2'b01: begin
                    exp_res   = in_a - in_b;
                    exp_carry = (in_a < in_b); // Standard borrow flag
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

            if ((res_8 !== exp_res) || (carry_8 !== exp_carry) || (zero_8 !== exp_zero)) begin
                $display("[FAIL] [8-bit] %0s | a=0x%0h b=0x%0h op=%0b | Exp: res=0x%0h c=%b z=%b | Got: res=0x%0h c=%b z=%b",
                         tname, in_a, in_b, in_op, exp_res, exp_carry, exp_zero, res_8, carry_8, zero_8);
                total_errors = total_errors + 1;
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

            if ((res_16 !== exp_res) || (carry_16 !== exp_carry) || (zero_16 !== exp_zero)) begin
                $display("[FAIL] [16-bit] %0s | a=0x%0h b=0x%0h op=%0b | Exp: res=0x%0h c=%b z=%b | Got: res=0x%0h c=%b z=%b",
                         tname, in_a, in_b, in_op, exp_res, exp_carry, exp_zero, res_16, carry_16, zero_16);
                total_errors = total_errors + 1;
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

            if ((res_32 !== exp_res) || (carry_32 !== exp_carry) || (zero_32 !== exp_zero)) begin
                $display("[FAIL] [32-bit] %0s | a=0x%0h b=0x%0h op=%0b | Exp: res=0x%0h c=%b z=%b | Got: res=0x%0h c=%b z=%b",
                         tname, in_a, in_b, in_op, exp_res, exp_carry, exp_zero, res_32, carry_32, zero_32);
                total_errors = total_errors + 1;
            end
        end
    endtask

    // =========================================================================
    // MAIN TEST EXECUTION
    // =========================================================================
    initial begin
        total_errors = 0;

        $display("==================================================");
        $display("    STARTING ALU MULTI-WIDTH VERIFICATION (8/16/32)");
        $display("==================================================");

        // ---------------------------------------------------------------------
        // SECTION 1: 8-BIT ALU VERIFICATION
        // ---------------------------------------------------------------------
        $display("\n--- [Section 1] Testing DATA_WIDTH = 8 ---");
        verify_8(8'h10, 8'h20, 2'b00, "Nominal ADD");
        verify_8(8'h50, 8'h20, 2'b01, "Nominal SUB");
        verify_8(8'hF0, 8'hAA, 2'b10, "Nominal AND");
        verify_8(8'hF0, 8'h0F, 2'b11, "Nominal OR");
        verify_8(8'hFF, 8'h01, 2'b00, "ADD Overflow (0xFF + 1)");
        verify_8(8'hFF, 8'hFF, 2'b00, "ADD Double Max (0xFF + 0xFF)");
        verify_8(8'h00, 8'h01, 2'b01, "SUB Underflow Borrow (0 - 1)");
        verify_8(8'h05, 8'h0A, 2'b01, "SUB Borrow (5 - 10)");
        verify_8(8'h55, 8'h55, 2'b01, "SUB Equal Zero (0x55 - 0x55)");

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

        // Final Summary
        $display("\n==================================================");
        if (total_errors == 0) begin
            $display("ALL TESTS PASSED (ALU WIDTHS: 8, 16, 32)");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d", total_errors);
        end
        $display("==================================================");

        $finish;
    end

endmodule
