# AutoVerify-VLSI: Comprehensive Verification & Audit Report

**Date:** November 2026  
**Environment:** Icarus Verilog (`iverilog -g2012`), VVP runtime, GTKWave  
**Regression Status:** 🟢 **ALL 3 MODULES PASSED (0 ERRORS)**  
**Pass Rate:** 100.0% across 1,000+ directed and constrained-random cycles  

---

## 1. Executive Summary

This report documents the verification audit, root-cause bug isolation, and hardening of the **AutoVerify-VLSI** IP portfolio:
1. **ALU (`dut/alu.v`)**: Parameterized Arithmetic Logic Unit
2. **Synchronous FIFO (`dut/sync_fifo.v`)**: Circular Pointer Multi-Word Buffer
3. **UART Transmitter (`dut/uart_tx.v`)**: Configurable Baud Rate & Parity Serializer

All modules were audited for functional race conditions, boundary limit bugs, reset behavior, and parity/framing compliance. Testbenches were re-engineered with negative-edge input driving and delta-delayed output sampling to eliminate simulator race conditions. Automated verification in `scripts/verify.py` was enhanced with exit code validation, watchdog timeouts, stale artifact elimination, and GitHub Actions CI.

---

## 2. RTL Bug Analysis & Engineering Fixes

### 2.1 Arithmetic Logic Unit (`dut/alu.v`)
- **Identified Defect:**
  In subtraction operations (`op = 2'b01`), subtraction underflow/borrow generation exhibited ambiguity between zero-extended arithmetic and reference model conventions.
- **Root Cause:**
  When evaluating `{carry, result} = a - b`, Verilog's vector extension conventions determine whether the 9th bit behaves as an active-high carry or an active-low borrow.
- **Implemented Fix:**
  - Standardized borrow flag definition explicitly across RTL and verification:
    ```verilog
    carry = (a < b); // Borrow flag: 1 on unsigned underflow, 0 otherwise
    ```
  - Added parameterized bitwidth `DATA_WIDTH` (default: 8).
  - Explicitly checked and verified the `zero` flag across all operations (`(result == 0)`).

### 2.2 Synchronous FIFO (`dut/sync_fifo.v`)
- **Identified Defects:**
  1. Boundary collision when simultaneous read and write occurred on an **empty** FIFO.
  2. Boundary collision when simultaneous read and write occurred on a **full** FIFO.
  3. Pointer wrap-around assumed power-of-two depths and lacked protection for arbitrary `DEPTH` parameters.
- **Root Cause:**
  The original RTL decremented count on read and incremented on write without properly prioritizing or isolating empty/full boundary conditions, allowing the count to wrap past zero or exceed capacity.
- **Implemented Fix:**
  - Standardized boundary behavior:
    - On **empty** (`count == 0`): If both read and write occur, write succeeds, read fails (underflow flag pulses), and count becomes 1.
    - On **full** (`count == DEPTH`): If both read and write occur, read succeeds, write fails (overflow flag pulses), and count becomes `DEPTH - 1`.
  - Replaced power-of-two bitmask indexing with modulo/wrap-around pointer arithmetic:
    ```verilog
    wr_ptr <= (wr_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
    rd_ptr <= (rd_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;
    ```
  - Made overflow and underflow sticky-safe single-cycle pulses during error conditions.

### 2.3 UART Transmitter (`dut/uart_tx.v`)
- **Identified Defects:**
  1. Premature stop-bit termination (`clk_count < 2` instead of `CLKS_PER_BIT - 1`).
  2. One-cycle phase lag on `tx` line during state transitions to `STATE_PARITY` and `STATE_STOP`.
  3. `tx_busy` remained asserted after transmission or failed to clear synchronously on completion.
- **Root Cause:**
  The injected stop bit bug ended the stop bit after 2 clock cycles instead of the configured `CLKS_PER_BIT - 1` baud cycles, causing framing errors during back-to-back transmissions. Updating `tx` sequentially inside states created a 1-cycle latency relative to baud counter boundaries.
- **Implemented Fix:**
  - Restored full stop-bit duration: `if (clk_count < CLKS_PER_BIT - 1)`.
  - Driven `tx` directly upon entering `STATE_STOP` and `STATE_PARITY` to guarantee immediate bit driving on state entry.
  - Cleared `tx_busy <= 1'b0` and asserted single-cycle `tx_done <= 1'b1` upon completion.
  - Validated all parity configurations:
    - Mode `2'b00`: No parity bit
    - Mode `2'b01`: Odd parity (`parity_bit = ~(^din)`)
    - Mode `2'b10`: Even parity (`parity_bit = ^din`)

---

## 3. Verification Environment & Testbench Architecture

### 3.1 Elimination of Clock-Edge Race Conditions
Previous testbenches drove DUT inputs and sampled outputs simultaneously on `@(posedge clk)`, creating non-deterministic simulator race conditions in Icarus Verilog.  
The testbenches were upgraded to standard industry practices:
- **Inputs Driven:** Exclusively on negative clock edges (`@(negedge clk)`).
- **Outputs Sampled:** Mid-cycle or at positive edges with explicit non-zero delta delay (`@(posedge clk); #1;`).

### 3.2 Reference Models & Test Suites
- **ALU (`testbenches/tb_alu.v`):**
  - Directed nominal operations (ADD, SUB, AND, OR).
  - Corner cases: arithmetic overflow (`0xFF + 0x01`), double-max add (`0xFF + 0xFF`), unsigned underflow (`0x00 - 0x01`), borrow (`0x05 - 0x0A`), identity subtraction (`0x55 - 0x55`), and zero results.
  - Constrained-random stress testing: 500 pseudorandom vectors verified against a behavioral golden model.
- **Synchronous FIFO (`testbenches/tb_sync_fifo.v`):**
  - Directed tests: single push/pop, drain to empty, fill to capacity (16 words).
  - Illegal boundary tests: read when empty (underflow flag check), write when full (overflow flag check).
  - Simultaneous operations: R/W on empty, R/W on full, R/W in steady-state.
  - Constrained-random stress testing: 500 random operations against an independent shadow queue reference model.
- **UART Transmitter (`testbenches/tb_uart_tx.v`):**
  - Directed tests across all parity modes: None, Odd, and Even with multiple test payloads (`0xA5`, `0x00`, `0xFF`, `0x55`, `0x3C`, `0x01`).
  - Cycle-by-cycle baud counter verification ensuring start bit is 0 for 10 cycles, data bits are correctly sequenced LSB-first, parity matches, and stop bit is 1 for the full baud duration.
  - Back-to-back zero-idle transmissions to confirm no framing or baud drift errors occur.
  - Constrained-random testing: 30 random frames with randomized data and parity configurations.

---

## 4. Measured Verification Results

All tests were executed on Windows using Icarus Verilog v12 and VVP:

```
=================================================================
 STARTING REGRESSION SUITE (3 Modules Found) 
=================================================================
[PASS] alu.v        : 0 Errors (Directed + 500 Random Vectors)
[PASS] sync_fifo.v  : 0 Errors (Directed + 500 Random Cycles)
[PASS] uart_tx.v    : 0 Errors (Directed + 30 Random Frames)
=================================================================
Overall Pass Rate: 100.0% (3/3 Passed, 0 Failed)
Regression Duration: ~4.2 seconds
```

---

## 5. Automated Verification Tooling (`scripts/verify.py`)

- **Deterministic Offline Verification:** `--no-ai` flag allows running 100% locally without external dependencies or API keys.
- **Stale Artifact Prevention:** Cleans `.vvp`, `.log`, and `.vcd` files before starting compilation.
- **Execution Safety:** Timeouts on compilation (20s) and simulation (15s) prevent hanging testbenches.
- **Exit Code Propagation:** Script returns exit code `0` on success and `1` on failure for CI/CD integration.
- **Safe AI Patch Isolation:** Candidate fixes generated by Gemini are isolated to `dut/<module>_candidate.v` and `logs/<module>_patch.diff` for engineer review. Validated RTL is never overwritten without explicit `--apply-candidate`.
