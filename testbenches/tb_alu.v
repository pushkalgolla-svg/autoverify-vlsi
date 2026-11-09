`timescale 1ns / 1ps

/**
 * Self-Checking Testbench for Parameterized ALU
 * Covers directed nominal tests, corner-case boundaries, and constrained-random stimulus.
 */

module tb_alu();

    parameter DATA_WIDTH = 8;

    // Signals for DUT connection
    reg  [DATA_WIDTH-1:0] a;
    reg  [DATA_WIDTH-1:0] b;
    reg  [1:0]            op;
    wire [DATA_WIDTH-1:0] result;
    wire                  carry;
    wire                  zero;

    // Testbench control variables
    integer error_count;
    integer i;

    // Expected values for scoreboard verification
    reg [DATA_WIDTH:0]   expected_sum;
    reg [DATA_WIDTH-1:0] expected_result;
    reg                  expected_carry;
    reg                  expected_zero;

    // Instantiate the DUT
    alu #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .a(a),
        .b(b),
        .op(op),
        .result(result),
        .carry(carry),
        .zero(zero)
    );

    // Watchdog timer to prevent infinite hangs
    initial begin
        #2000000;
        $display("[ERROR] Watchdog timeout: simulation hung!");
        $finish;
    end

    // VCD Waveform Generation (portable relative path)
    initial begin
        $dumpfile("logs/alu.vcd");
        $dumpvars(0, tb_alu);
    end

    // Task to check outputs against golden model
    task check_case(input [255:0] test_name);
        begin
            #1; // Allow combinational outputs to settle
            if ((result !== expected_result) || (carry !== expected_carry) || (zero !== expected_zero)) begin
                $display("[FAIL] %0s | Inputs: a=0x%0h b=0x%0h op=%0b | Expected: res=0x%0h c=%0b z=%0b | Got: res=0x%0h c=%0b z=%0b",
                         test_name, a, b, op, expected_result, expected_carry, expected_zero, result, carry, zero);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] %0s | res=0x%0h c=%0b z=%0b", test_name, result, carry, zero);
            end
        end
    endtask

    // Main Test Sequence
    initial begin
        error_count = 0;
        a  = {DATA_WIDTH{1'b0}};
        b  = {DATA_WIDTH{1'b0}};
        op = 2'b00;
        #10;

        $display("========================================");
        $display("   STARTING ALU VERIFICATION BENCHMARK");
        $display("========================================");

        //------------------------------------------------------------------
        // 1. DIRECTED NOMINAL TESTS
        //------------------------------------------------------------------
        $display("\n--- Running Directed Nominal Tests ---");

        // ADD: 0x10 + 0x20 = 0x30, carry = 0, zero = 0
        a = 8'h10; b = 8'h20; op = 2'b00;
        expected_result = 8'h30; expected_carry = 1'b0; expected_zero = 1'b0;
        check_case("ADD 0x10 + 0x20");

        // SUB: 0x50 - 0x20 = 0x30, carry(borrow) = 0, zero = 0
        a = 8'h50; b = 8'h20; op = 2'b01;
        expected_result = 8'h30; expected_carry = 1'b0; expected_zero = 1'b0;
        check_case("SUB 0x50 - 0x20");

        // AND: 0xF0 & 0xAA = 0xA0, carry = 0, zero = 0
        a = 8'hF0; b = 8'hAA; op = 2'b10;
        expected_result = 8'hA0; expected_carry = 1'b0; expected_zero = 1'b0;
        check_case("AND 0xF0 & 0xAA");

        // OR: 0xF0 | 0x0F = 0xFF, carry = 0, zero = 0
        a = 8'hF0; b = 8'h0F; op = 2'b11;
        expected_result = 8'hFF; expected_carry = 1'b0; expected_zero = 1'b0;
        check_case("OR 0xF0 | 0x0F");

        //------------------------------------------------------------------
        // 2. CORNER CASES AND BOUNDARY CONDITIONS
        //------------------------------------------------------------------
        $display("\n--- Running Corner Cases and Edge Conditions ---");

        // ADD Overflow: 0xFF + 0x01 = 0x00, carry = 1, zero = 1
        a = 8'hFF; b = 8'h01; op = 2'b00;
        expected_result = 8'h00; expected_carry = 1'b1; expected_zero = 1'b1;
        check_case("ADD Overflow (0xFF + 0x01)");

        // ADD Boundary: 0xFF + 0xFF = 0xFE, carry = 1, zero = 0
        a = 8'hFF; b = 8'hFF; op = 2'b00;
        expected_result = 8'hFE; expected_carry = 1'b1; expected_zero = 1'b0;
        check_case("ADD Max (0xFF + 0xFF)");

        // SUB Underflow / Borrow: 0x00 - 0x01 = 0xFF, carry(borrow) = 1, zero = 0
        a = 8'h00; b = 8'h01; op = 2'b01;
        expected_result = 8'hFF; expected_carry = 1'b1; expected_zero = 1'b0;
        check_case("SUB Underflow (0x00 - 0x01)");

        // SUB Underflow / Borrow: 0x05 - 0x0A = 0xFB, carry(borrow) = 1, zero = 0
        a = 8'h05; b = 8'h0A; op = 2'b01;
        expected_result = 8'hFB; expected_carry = 1'b1; expected_zero = 1'b0;
        check_case("SUB Borrow (0x05 - 0x0A)");

        // SUB Identical: 0x55 - 0x55 = 0x00, carry(borrow) = 0, zero = 1
        a = 8'h55; b = 8'h55; op = 2'b01;
        expected_result = 8'h00; expected_carry = 1'b0; expected_zero = 1'b1;
        check_case("SUB Equal (0x55 - 0x55)");

        // AND Zero: 0x55 & 0xAA = 0x00, carry = 0, zero = 1
        a = 8'h55; b = 8'hAA; op = 2'b10;
        expected_result = 8'h00; expected_carry = 1'b0; expected_zero = 1'b1;
        check_case("AND Complement (0x55 & 0xAA)");

        // OR Zero: 0x00 | 0x00 = 0x00, carry = 0, zero = 1
        a = 8'h00; b = 8'h00; op = 2'b11;
        expected_result = 8'h00; expected_carry = 1'b0; expected_zero = 1'b1;
        check_case("OR Zero (0x00 | 0x00)");

        //------------------------------------------------------------------
        // 3. CONSTRAINED-RANDOM STRESS TESTING
        //------------------------------------------------------------------
        $display("\n--- Running Constrained-Random Stress Tests ---");

        for (i = 0; i < 500; i = i + 1) begin
            a  = $random & 8'hFF;
            b  = $random & 8'hFF;
            op = $random & 2'b11;

            case (op)
                2'b00: begin
                    expected_sum    = a + b;
                    expected_result = expected_sum[7:0];
                    expected_carry  = expected_sum[8];
                end
                2'b01: begin
                    expected_result = a - b;
                    expected_carry  = (a < b); // Borrow flag
                end
                2'b10: begin
                    expected_result = a & b;
                    expected_carry  = 1'b0;
                end
                2'b11: begin
                    expected_result = a | b;
                    expected_carry  = 1'b0;
                end
            endcase
            expected_zero = (expected_result == 8'h00);

            #1;
            if ((result !== expected_result) || (carry !== expected_carry) || (zero !== expected_zero)) begin
                $display("[FAIL] Random iter %0d: a=0x%0h b=0x%0h op=%0b | Expected: res=0x%0h c=%0b z=%0b | Got: res=0x%0h c=%0b z=%0b",
                         i, a, b, op, expected_result, expected_carry, expected_zero, result, carry, zero);
                error_count = error_count + 1;
            end
        end
        $display("[PASS] Completed 500 constrained-random test vectors.");

        //------------------------------------------------------------------
        // FINAL RESULTS SUMMARY
        //------------------------------------------------------------------
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
