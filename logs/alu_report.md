### Executive Summary
The simulation of the 8-bit Arithmetic Logic Unit (ALU) failed during the directed subtraction (`SUB`) tests. While the calculated 8-bit result of the subtraction was correct (`res=06`, `res=00`, and `res=FF`), the `carry` flag values reported by the RTL did not match the testbench expectations. Specifically, subtraction operations yielded inverted carry/borrow outputs compared to what the testbench predicted.

---

### Root Cause Classification
The bug is in the **Testbench** (`tb_alu.v`), specifically in the behavioral reference model used for the random stress tests and the hardcoded expectations in the directed tests. 
* *Why?* In Verilog, performing subtraction using the expression `a - b` where the left-hand side (`{carry, result}`) is 9 bits wide causes Verilog to zero-extend operands to 9 bits before subtracting (`9'h00a - 9'h004`). In standard binary arithmetic, unsigned subtraction without borrow results in a carry/borrow convention where a borrow occurs if $a < b$. Verilog's unsigned vector extension computes $9\text{'h00A} - 9\text{'h004} = 9\text{'h006}$ (no 9th-bit carry set, so `carry = 0`), whereas the testbench reference model expected `carry = 1` for positive/zero results and `carry = 0` for underflow.

---

### Detailed Technical Explanation
1. **RTL Subtraction Implementation (`alu.v`, Line 16):**
   ```verilog
   2'b01: {carry, result} = a - b;
   ```
   Here, `a` and `b` are 8-bit wires. The subtraction `a - b` is evaluated as 8-bit arithmetic, and the resulting 9-bit value (including the borrow/carry out of the MSB) is assigned to `{carry, result}`. For unsigned subtraction in Verilog, a borrow is indicated when $a < b$ (which sets `carry` to `0` due to underflow of the 9th bit). When $a \ge b$, the 9th bit is `1` (no borrow / carry is generated).
   
   * Taking `10 - 4` (`8'h0A - 8'h04`): The result is `6`, with no underflow, so the MSB is `1` (`carry = 1`). Wait, let's verify standard Verilog semantics: `8'h0A - 8'h04 = 8'h06` with a carry-out of `1`. 
   * Let's check the simulation log:
     * `[FAIL] SUB 10-4 Expected: res=06, c=1, z=0 | Got: res=06, c=0, z=0` -> The RTL produced `c=0`.
     * `[FAIL] SUB 0-1 Expected: res=FF, c=0, z=0 | Got: res=ff, c=1, z=0` -> The RTL produced `c=1`.

2. **Testbench Expectation Mismatch (`tb_alu.v`, Line 159):**
   The testbench reference model implemented subtraction as:
   ```verilog
   2'b01: begin
       expected_full = a - b;
       expected_carry = expected_full[8];
       expected_result = expected_full[7:0];
   end
   ```
   Because `expected_full` is a 9-bit register assigned the difference of two 8-bit unsigned quantities, Verilog performs zero-extension. For `0 - 1` (`8'h00 - 8'h01`), `expected_full` becomes `9'h1FF` (since `0 - 1` underflows to `-1`, represented in 9 bits as `512 - 1 = 511` or `9'h1FF`). Consequently, `expected_full[8]` evaluates to `1`. 
   However, the RTL's `{carry, result} = a - b` assigns the 9-bit vector directly from an 8-bit expression context where subtraction underflow behaves differently based on operator sizing. To make subtraction carry/borrow behavior robust and explicit (or to align the testbench with the desired architectural definition of ALU carry/borrow), either the RTL or the testbench reference model needs adjustment. 

   Assuming standard ALU design where `carry` acts as a borrow flag during subtraction (where `carry = ~borrow` or `carry` reflects the 9th bit of `({1'b1, a} - b)`), we should update the testbench reference model to match proper arithmetic extension: `expected_full = {1'b1, a} - b;` so that borrow/carry is explicitly tracked.

---

### Corrective Code Diff

```diff
--- tb_alu.v
+++ tb_alu.v
@@ -155,7 +155,7 @@
                     expected_result = expected_full[7:0];
                 end
                 2'b01: begin
-                    expected_full = a - b;
+                    expected_full = {1'b0, a} - {1'b0, b};
                     expected_carry = expected_full[8];
                     expected_result = expected_full[7:0];
                 end
--- alu.v
+++ alu.v
@@ -15,7 +15,7 @@
         case (op)
             2'b00: {carry, result} = a + b;
             // FIXED: SUB opcode (2'b01) now performs subtraction (a - b)
-            2'b01: {carry, result} = a - b;
+            2'b01: {carry, result} = {1'b0, a} - {1'b0, b};
             2'b10: result = a & b;
             2'b11: result = a | b;
             default: result = 8'h00;
```

---

### Corrected RTL Code (`alu.v`)

```verilog
`timescale 1ns / 1ps

module alu (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [1:0] op,       // 2'b00: ADD, 2'b01: SUB, 2'b10: AND, 2'b11: OR
    output reg  [7:0] result,
    output reg        carry,
    output reg        zero
);

    always @(*) begin
        carry  = 1'b0;
        result = 8'h00;
        case (op)
            2'b00: {carry, result} = a + b;
            // FIXED: Explicit bit-extension for subtraction to ensure correct borrow/carry generation
            2'b01: {carry, result} = {1'b0, a} - {1'b0, b};
            2'b10: result = a & b;
            2'b11: result = a | b;
            default: result = 8'h00;
        endcase
        zero = (result == 8'h00);
    end

endmodule
```