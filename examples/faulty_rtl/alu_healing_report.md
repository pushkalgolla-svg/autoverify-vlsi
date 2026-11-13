# AutoVerify-VLSI: AI-Assisted Self-Healing Diagnostic Report

**Mode:** Deterministic Offline Demonstration Mode  
**Target Module:** `examples/faulty_rtl/alu_faulty.v`  
**Defect Classification:** 🔴 **RTL Design Defect** (Logic Inversion)  

---

## 1. Executive Summary
The simulation of `alu_faulty.v` failed multiple directed and randomized test assertions under subtraction operations (`op = 2'b01`).
Specifically, when an unsigned underflow occurred (`a < b`, e.g., `0 - 1`), the ALU outputted `carry = 0` instead of asserting the borrow flag (`carry = 1`). Conversely, when `a > b`, `carry` was incorrectly asserted as `1`.

---

## 2. Root Cause Analysis
- **Location:** Line 34 of `examples/faulty_rtl/alu_faulty.v`
- **Faulty Expression:** `carry = (a > b);`
- **Root Cause:** The borrow condition comparison was inverted. In standard unsigned binary subtraction, a borrow (underflow) occurs when the minuend `a` is strictly less than the subtrahend `b` (`a < b`).

---

## 3. Corrective Patch
```diff
--- a/examples/faulty_rtl/alu_faulty.v
+++ b/examples/faulty_rtl/alu_candidate.v
@@ -31,3 +31,3 @@
             2'b01: begin
                 result = a - b;
-                carry  = (a > b); // INJECTED DEFECT: Inverted comparison condition!
+                carry  = (a < b); // Explicit borrow indicator: 1 if underflow (a < b)
             end
```

---

## 4. Corrected RTL Code
```verilog
`timescale 1ns / 1ps

/**
 * Corrected Parameterized ALU (Demonstration Candidate)
 * Fix: Standardized subtraction borrow condition:
 *   carry = (a < b); // Borrow flag: 1 if unsigned underflow (a < b)
 */

module alu #(
    parameter DATA_WIDTH = 8
) (
    input  wire [DATA_WIDTH-1:0] a,
    input  wire [DATA_WIDTH-1:0] b,
    input  wire [1:0]            op,
    output reg  [DATA_WIDTH-1:0] result,
    output reg                   carry,
    output reg                   zero
);

    always @(*) begin
        carry  = 1'b0;
        result = {DATA_WIDTH{1'b0}};
        case (op)
            2'b00: {carry, result} = a + b;
            2'b01: begin
                result = a - b;
                carry  = (a < b); // Explicit borrow indicator: 1 if underflow (a < b)
            end
            2'b10: result = a & b;
            2'b11: result = a | b;
            default: begin
                result = {DATA_WIDTH{1'b0}};
                carry  = 1'b0;
            end
        endcase
        zero = (result == {DATA_WIDTH{1'b0}});
    end

endmodule
```
