`timescale 1ns / 1ps

module tb_alu();

    // Signals
    reg  [7:0] a;
    reg  [7:0] b;
    reg  [1:0] op;
    wire [7:0] result;
    wire       carry;
    wire       zero;

    // Testbench control variables
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

    initial begin
        // VCD Waveform Generation
        $dumpfile("C:/Users/91900/.gemini/antigravity/scratch/ai_verification/logs/alu.vcd");
        $dumpvars(0, tb_alu);

        // Initialize variables
        error_count = 0;
        a = 8'h00;
        b = 8'h00;
        op = 2'b00;

        #10;

        // ========================================================
        // 1. DIRECTED TESTS: ADD Operation (2'b00)
        // ========================================================
        $display("--- Starting Directed Tests: ADD ---");
        
        a = 8'h00; b = 8'h00; op = 2'b00; #10;
        if (result !== 8'h00 || carry !== 1'b0 || zero !== 1'b1) begin
            $display("[FAIL] ADD 0+0 Expected: res=00, c=0, z=1 | Got: res=%h, c=%b, z=%b", result, carry, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] ADD 0+0");
        end

        a = 8'h05; b = 8'h03; op = 2'b00; #10;
        if (result !== 8'h08 || carry !== 1'b0 || zero !== 1'b0) begin
            $display("[FAIL] ADD 5+3 Expected: res=08, c=0, z=0 | Got: res=%h, c=%b, z=%b", result, carry, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] ADD 5+3");
        end

        a = 8'hFF; b = 8'h01; op = 2'b00; #10;
        if (result !== 8'h00 || carry !== 1'b1 || zero !== 1'b1) begin
            $display("[FAIL] ADD FF+01 Expected: res=00, c=1, z=1 | Got: res=%h, c=%b, z=%b", result, carry, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] ADD FF+01 (Overflow)");
        end

        // ========================================================
        // 2. DIRECTED TESTS: SUB Operation (2'b01)
        // ========================================================
        $display("--- Starting Directed Tests: SUB ---");

        a = 8'h0A; b = 8'h04; op = 2'b01; #10;
        if (result !== 8'h06 || carry !== 1'b1 || zero !== 1'b0) begin
            $display("[FAIL] SUB 10-4 Expected: res=06, c=1, z=0 | Got: res=%h, c=%b, z=%b", result, carry, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] SUB 10-4");
        end

        a = 8'h05; b = 8'h05; op = 2'b01; #10;
        if (result !== 8'h00 || carry !== 1'b1 || zero !== 1'b1) begin
            $display("[FAIL] SUB 5-5 Expected: res=00, c=1, z=1 | Got: res=%h, c=%b, z=%b", result, carry, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] SUB 5-5 (Zero Result)");
        end

        a = 8'h00; b = 8'h01; op = 2'b01; #10;
        if (result !== 8'hFF || carry !== 1'b0 || zero !== 1'b0) begin
            $display("[FAIL] SUB 0-1 Expected: res=FF, c=0, z=0 | Got: res=%h, c=%b, z=%b", result, carry, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] SUB 0-1 (Underflow)");
        end

        // ========================================================
        // 3. DIRECTED TESTS: AND Operation (2'b10)
        // ========================================================
        $display("--- Starting Directed Tests: AND ---");

        a = 8'hF0; b = 8'h0F; op = 2'b10; #10;
        if (result !== 8'h00 || zero !== 1'b1) begin
            $display("[FAIL] AND F0&0F Expected: res=00, z=1 | Got: res=%h, z=%b", result, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] AND F0&0F");
        end

        a = 8'hA5; b = 8'h5A; op = 2'b10; #10;
        if (result !== 8'h00 || zero !== 1'b1) begin
            $display("[FAIL] AND A5&5A Expected: res=00, z=1 | Got: res=%h, z=%b", result, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] AND A5&5A");
        end

        a = 8'hAA; b = 8'hCC; op = 2'b10; #10;
        if (result !== 8'h88 || zero !== 1'b0) begin
            $display("[FAIL] AND AA&CC Expected: res=88, z=0 | Got: res=%h, z=%b", result, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] AND AA&CC");
        end

        // ========================================================
        // 4. DIRECTED TESTS: OR Operation (2'b11)
        // ========================================================
        $display("--- Starting Directed Tests: OR ---");

        a = 8'hF0; b = 8'h0F; op = 2'b11; #10;
        if (result !== 8'hFF || zero !== 1'b0) begin
            $display("[FAIL] OR F0|0F Expected: res=FF, z=0 | Got: res=%h, z=%b", result, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] OR F0|0F");
        end

        a = 8'h00; b = 8'h00; op = 2'b11; #10;
        if (result !== 8'h00 || zero !== 1'b1) begin
            $display("[FAIL] OR 00|00 Expected: res=00, z=1 | Got: res=%h, z=%b", result, zero);
            error_count = error_count + 1;
        end else begin
            $display("[PASS] OR 00|00");
        end

        // ========================================================
        // 5. CONSTRAINED-RANDOM STRESS TESTING
        // ========================================================
        $display("--- Starting Constrained-Random Stress Test ---");
        
        for (i = 0; i < 200; i = i + 1) begin
            a  = $random & 8'hFF;
            b  = $random & 8'hFF;
            op = $random & 2'b11;
            #5;

            // Compute expected values using behavioral model
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

            // Self-check assertions
            if ((result !== expected_result) || 
                ((op == 2'b00 || op == 2'b01) && (carry !== expected_carry)) || 
                (zero !== expected_zero)) begin
                $display("[FAIL] Random Test Mismatch: op=%b, a=%h, b=%h | Expected: res=%h, c=%b, z=%b | Got: res=%h, c=%b, z=%b",
                         op, a, b, expected_result, expected_carry, expected_zero, result, carry, zero);
                error_count = error_count + 1;
            end
        end

        $display("--- Random Stress Testing Complete ---");

        // ========================================================
        // SUMMARY REPORT
        // ========================================================
        if (error_count == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SIMULATION FAILED: Total Errors = %0d", error_count);
        end

        $finish;
    end

endmodule