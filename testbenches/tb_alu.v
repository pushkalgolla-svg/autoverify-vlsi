`timescale 1ns / 1ps

module alu_tb;

    // DUT Inputs
    reg [7:0] a_tb;
    reg [7:0] b_tb;
    reg [1:0] op_tb;

    // DUT Outputs
    wire [7:0] result_tb;
    wire       carry_tb;
    wire       zero_tb;

    // Error Counter
    integer error_count = 0;

    // Instantiate DUT
    alu dut (
        .a(a_tb),
        .b(b_tb),
        .op(op_tb),
        .result(result_tb),
        .carry(carry_tb),
        .zero(zero_tb)
    );

    // Task to apply stimulus, check results, and report status
    task run_test;
        input [7:0]  test_a;
        input [7:0]  test_b;
        input [1:0]  test_op;
        input [7:0]  exp_result;
        input        exp_carry;
        input        exp_zero;
        input string op_name; // String to identify the operation

        begin
            a_tb  = test_a;
            b_tb  = test_b;
            op_tb = test_op;

            // Wait for combinational logic to settle
            #10;

            if (result_tb == exp_result && carry_tb == exp_carry && zero_tb == exp_zero) begin
                $display("[PASS] %s: a=0x%02x, b=0x%02x, op=%b, result=0x%02x, carry=%b, zero=%b",
                         op_name, a_tb, b_tb, op_tb, result_tb, carry_tb, zero_tb);
            end else begin
                $display("[FAIL] %s: a=0x%02x, b=0x%02x, op=%b", op_name, a_tb, b_tb, op_tb);
                $display("       Expected: result=0x%02x, carry=%b, zero=%b", exp_result, exp_carry, exp_zero);
                $display("       Got:      result=0x%02x, carry=%b, zero=%b", result_tb, carry_tb, zero_tb);
                error_count = error_count + 1;
            end
        end
    endtask

    // Initial block for test stimulus generation
    initial begin
        // Initialize inputs to a known state
        a_tb = 8'h00;
        b_tb = 8'h00;
        op_tb = 2'b00;
        #10; // Allow initial values to propagate and DUT to settle

        $display("--------------------------------------------------");
        $display("       Starting ALU Testbench Simulation          ");
        $display("--------------------------------------------------");

        // --------------------------------------------------------------------
        // ADD Operation (op = 2'b00)
        // {carry, result} = a + b
        // carry acts as an overflow for unsigned addition
        $display("\n--- Testing ADD (op=2'b00) ---");
        // Test Case 1: 0 + 0 = 0 (no carry, zero flag set)
        run_test(8'h00, 8'h00, 2'b00, 8'h00, 1'b0, 1'b1, "ADD");
        // Test Case 2: 5 + 10 = 15 (no carry, no zero)
        run_test(8'h05, 8'h0A, 2'b00, 8'h0F, 1'b0, 1'b0, "ADD");
        // Test Case 3: 255 + 1 = 0 (overflow, carry set, zero flag set)
        run_test(8'hFF, 8'h01, 2'b00, 8'h00, 1'b1, 1'b1, "ADD");
        // Test Case 4: 127 + 128 = 255 (no carry, no zero)
        run_test(8'h7F, 8'h80, 2'b00, 8'hFF, 1'b0, 1'b0, "ADD");
        // Test Case 5: 128 + 128 = 0 (overflow, carry set, zero flag set)
        run_test(8'h80, 8'h80, 2'b00, 8'h00, 1'b1, 1'b1, "ADD");

        // --------------------------------------------------------------------
        // SUB Operation (op = 2'b01)
        // {carry, result} = a - b
        // carry acts as a borrow flag (1 if a < b, 0 if a >= b)
        $display("\n--- Testing SUB (op=2'b01) ---");
        // Test Case 1: 0 - 0 = 0 (no borrow, zero flag set)
        run_test(8'h00, 8'h00, 2'b01, 8'h00, 1'b0, 1'b1, "SUB");
        // Test Case 2: 10 - 5 = 5 (no borrow, no zero)
        run_test(8'h0A, 8'h05, 2'b01, 8'h05, 1'b0, 1'b0, "SUB");
        // Test Case 3: 5 - 10 = -5 (underflow, borrow set, 251 unsigned)
        run_test(8'h05, 8'h0A, 2'b01, 8'hFB, 1'b1, 1'b0, "SUB");
        // Test Case 4: 1 - 255 = 2 (underflow, borrow set, 2 unsigned)
        run_test(8'h01, 8'hFF, 2'b01, 8'h02, 1'b1, 1'b0, "SUB");
        // Test Case 5: 128 - 128 = 0 (no borrow, zero flag set)
        run_test(8'h80, 8'h80, 2'b01, 8'h00, 1'b0, 1'b1, "SUB");

        // --------------------------------------------------------------------
        // AND Operation (op = 2'b10)
        // result = a & b, carry = 0
        $display("\n--- Testing AND (op=2'b10) ---");
        // Test Case 1: 0 & 0 = 0 (carry=0, zero=1)
        run_test(8'h00, 8'h00, 2'b10, 8'h00, 1'b0, 1'b1, "AND");
        // Test Case 2: FF & FF = FF (carry=0, zero=0)
        run_test(8'hFF, 8'hFF, 2'b10, 8'hFF, 1'b0, 1'b0, "AND");
        // Test Case 3: AA & 55 = 0 (carry=0, zero=1)
        run_test(8'hAA, 8'h55, 2'b10, 8'h00, 1'b0, 1'b1, "AND");
        // Test Case 4: F0 & 0F = 0 (carry=0, zero=1)
        run_test(8'hF0, 8'h0F, 2'b10, 8'h00, 1'b0, 1'b1, "AND");
        // Test Case 5: F0 & A0 = A0 (carry=0, zero=0)
        run_test(8'hF0, 8'hA0, 2'b10, 8'hA0, 1'b0, 1'b0, "AND");

        // --------------------------------------------------------------------
        // OR Operation (op = 2'b11)
        // result = a | b, carry = 0
        $display("\n--- Testing OR (op=2'b11) ---");
        // Test Case 1: 0 | 0 = 0 (carry=0, zero=1)
        run_test(8'h00, 8'h00, 2'b11, 8'h00, 1'b0, 1'b1, "OR");
        // Test Case 2: FF | FF = FF (carry=0, zero=0)
        run_test(8'hFF, 8'hFF, 2'b11, 8'hFF, 1'b0, 1'b0, "OR");
        // Test Case 3: AA | 55 = FF (carry=0, zero=0)
        run_test(8'hAA, 8'h55, 2'b11, 8'hFF, 1'b0, 1'b0, "OR");
        // Test Case 4: F0 | 0F = FF (carry=0, zero=0)
        run_test(8'hF0, 8'h0F, 2'b11, 8'hFF, 1'b0, 1'b0, "OR");
        // Test Case 5: F0 | A0 = F0 (carry=0, zero=0)
        run_test(8'hF0, 8'hA0, 2'b11, 8'hF0, 1'b0, 1'b0, "OR");

        // --------------------------------------------------------------------
        // Final Summary
        $display("\n--------------------------------------------------");
        if (error_count == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d", error_count);
        end
        $display("--------------------------------------------------");

        $finish; // Terminate simulation
    end

endmodule