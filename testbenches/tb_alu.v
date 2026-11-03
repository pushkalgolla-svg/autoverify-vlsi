`timescale 1ns / 1ps

module tb_alu;

    // Testbench signals
    reg  [7:0] a;
    reg  [7:0] b;
    reg  [1:0] op;
    wire [7:0] result;
    wire       carry;
    wire       zero;

    // Control and checking variables
    integer error_count;
    integer i;
    reg [8:0] expected_full;
    reg [7:0] expected_result;
    reg       expected_carry;
    reg       expected_zero;

    // Instantiate the DUT
    alu dut (
        .a(a),
        .b(b),
        .op(op),
        .result(result),
        .carry(carry),
        .zero(zero)
    );

    // Initial block for simulation setup and test execution
    initial begin
        // Setup VCD dumping
        $dumpfile("C:/Users/91900/.gemini/antigravity/scratch/ai_verification/logs/alu.vcd");
        $dumpvars(0, tb_alu);

        // Initialize variables
        error_count = 0;
        a = 8'h00;
        b = 8'h00;
        op = 2'b00;

        #10;

        // ==========================================
        // 1. DIRECTED NOMINAL TESTS
        // ==========================================
        
        // Test ADD: 5 + 3 = 8
        a = 8'd5;
        b = 8'd3;
        op = 2'b00;
        #10;
        expected_full = a + b;
        expected_carry = expected_full[8];
        expected_result = expected_full[7:0];
        expected_zero = (expected_result == 8'h00);
        
        if ((result === expected_result) && (carry === expected_carry) && (zero === expected_zero)) begin
            $display("[PASS] ADD nominal test: 5 + 3 = 8");
        end else begin
            $display("[FAIL] ADD nominal test: 5 + 3. Expected [Res: %0h, Carry: %b, Zero: %b], Got [Res: %0h, Carry: %b, Zero: %b]", 
                     expected_result, expected_carry, expected_zero, result, carry, zero);
            error_count = error_count + 1;
        end

        // Test SUB: 10 - 4 = 6
        a = 8'd10;
        b = 8'd4;
        op = 2'b01;
        #10;
        expected_full = a - b;
        expected_carry = expected_full[8];
        expected_result = expected_full[7:0];
        expected_zero = (expected_result == 8'h00);
        
        if ((result === expected_result) && (carry === expected_carry) && (zero === expected_zero)) begin
            $display("[PASS] SUB nominal test: 10 - 4 = 6");
        end else begin
            $display("[FAIL] SUB nominal test: 10 - 4. Expected [Res: %0h, Carry: %b, Zero: %b], Got [Res: %0h, Carry: %b, Zero: %b]", 
                     expected_result, expected_carry, expected_zero, result, carry, zero);
            error_count = error_count + 1;
        end

        // Test AND: 8'hF0 & 8'hAA = 8'hA0
        a = 8'hF0;
        b = 8'hAA;
        op = 2'b10;
        #10;
        expected_carry = 1'b0;
        expected_result = a & b;
        expected_zero = (expected_result == 8'h00);
        
        if ((result === expected_result) && (carry === expected_carry) && (zero === expected_zero)) begin
            $display("[PASS] AND nominal test: 0xF0 & 0xAA = 0xA0");
        end else begin
            $display("[FAIL] AND nominal test: 0xF0 & 0xAA. Expected [Res: %0h, Carry: %b, Zero: %b], Got [Res: %0h, Carry: %b, Zero: %b]", 
                     expected_result, expected_carry, expected_zero, result, carry, zero);
            error_count = error_count + 1;
        end

        // Test OR: 8'h0F | 8'h33 = 8'h3F
        a = 8'h0F;
        b = 8'h33;
        op = 2'b11;
        #10;
        expected_carry = 1'b0;
        expected_result = a | b;
        expected_zero = (expected_result == 8'h00);
        
        if ((result === expected_result) && (carry === expected_carry) && (zero === expected_zero)) begin
            $display("[PASS] OR nominal test: 0x0F | 0x33 = 0x3F");
        end else begin
            $display("[FAIL] OR nominal test: 0x0F | 0x33. Expected [Res: %0h, Carry: %b, Zero: %b], Got [Res: %0h, Carry: %b, Zero: %b]", 
                     expected_result, expected_carry, expected_zero, result, carry, zero);
            error_count = error_count + 1;
        end

        // ==========================================
        // 2. CORNER CASES AND EDGE CONDITIONS
        // ==========================================

        // ADD Overflow: 255 + 1 = 256 (Carry = 1, Result = 0, Zero = 1)
        a = 8'hFF;
        b = 8'h01;
        op = 2'b00;
        #10;
        expected_full = a + b;
        expected_carry = expected_full[8];
        expected_result = expected_full[7:0];
        expected_zero = (expected_result == 8'h00);
        
        if ((result === expected_result) && (carry === expected_carry) && (zero === expected_zero)) begin
            $display("[PASS] ADD overflow test: 255 + 1 = 0 with Carry");
        end else begin
            $display("[FAIL] ADD overflow test. Expected [Res: %0h, Carry: %b, Zero: %b], Got [Res: %0h, Carry: %b, Zero: %b]", 
                     expected_result, expected_carry, expected_zero, result, carry, zero);
            error_count = error_count + 1;
        end

        // SUB Underflow / Borrow: 0 - 1 = 255 (Carry = 1 due to borrow in Verilog subtraction, Result = 255, Zero = 0)
        a = 8'h00;
        b = 8'h01;
        op = 2'b01;
        #10;
        expected_full = a - b;
        expected_carry = expected_full[8];
        expected_result = expected_full[7:0];
        expected_zero = (expected_result == 8'h00);
        
        if ((result === expected_result) && (carry === expected_carry) && (zero === expected_zero)) begin
            $display("[PASS] SUB underflow test: 0 - 1 = 255");
        end else begin
            $display("[FAIL] SUB underflow test. Expected [Res: %0h, Carry: %b, Zero: %b], Got [Res: %0h, Carry: %b, Zero: %b]", 
                     expected_result, expected_carry, expected_zero, result, carry, zero);
            error_count = error_count + 1;
        end

        // Zero Flag Check via Subtraction: 5 - 5 = 0 (Zero = 1)
        a = 8'd5;
        b = 8'd5;
        op = 2'b01;
        #10;
        expected_full = a - b;
        expected_carry = expected_full[8];
        expected_result = expected_full[7:0];
        expected_zero = (expected_result == 8'h00);
        
        if ((result === expected_result) && (carry === expected_carry) && (zero === expected_zero)) begin
            $display("[PASS] Zero flag test via SUB: 5 - 5 = 0");
        end else begin
            $display("[FAIL] Zero flag test via SUB. Expected [Res: %0h, Carry: %b, Zero: %b], Got [Res: %0h, Carry: %b, Zero: %b]", 
                     expected_result, expected_carry, expected_zero, result, carry, zero);
            error_count = error_count + 1;
        end

        // ==========================================
        // 3. CONSTRAINED-RANDOM STRESS TESTING
        // ==========================================
        $display("[INFO] Starting random stress testing...");
        for (i = 0; i < 100; i = i + 1) begin
            a = $random & 8'hFF;
            b = $random & 8'hFF;
            op = $random & 2'b11;
            #5;

            // Compute expected value based on opcode
            case (op)
                2'b00: begin
                    expected_full = a + b;
                    expected_carry = expected_full[8];
                    expected_result = expected_full[7:0];
                end
                2'b01: begin
                    expected_full = a - b;
                    expected_carry = expected_full[8];
                    expected_result = expected_full[7:0];
                end
                2'b10: begin
                    expected_carry = 1'b0;
                    expected_result = a & b;
                end
                2'b11: begin
                    expected_carry = 1'b0;
                    expected_result = a | b;
                end
                default: begin
                    expected_carry = 1'b0;
                    expected_result = 8'h00;
                end
            endcase
            expected_zero = (expected_result == 8'h00);

            if ((result !== expected_result) || (carry !== expected_carry) || (zero !== expected_zero)) begin
                $display("[FAIL] Random Test Mismatch: op=%b, a=%0h, b=%0h | Expected [Res: %0h, Carry: %b, Zero: %b] | Got [Res: %0h, Carry: %b, Zero: %b]",
                         op, a, b, expected_result, expected_carry, expected_zero, result, carry, zero);
                error_count = error_count + 1;
            end
        end
        $display("[INFO] Random stress testing completed.");

        // ==========================================
        // 4. CONCLUSION AND SUMMARY
        // ==========================================
        #10;
        if (error_count == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d", error_count);
        end
        $finish;
    end

endmodule