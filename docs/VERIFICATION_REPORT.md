# AutoVerify-VLSI: Comprehensive Verification & Audit Report

**Date:** November 2026  
**Environment:** Icarus Verilog (`iverilog -g2012`), VVP runtime, GTKWave  
**Regression Status:** 🟢 **ALL 3 MODULES PASSED (0 ERRORS)**  
**Pass Rate:** 100.0% across 1,600+ directed, parameterized, and constrained-random cycles  

---

## 1. Executive Summary

This report documents the verification audit, root-cause bug isolation, parameter hardening, and CI automation of the **AutoVerify-VLSI** digital IP portfolio:
1. **ALU (`dut/alu.v`)**: Parameterized Arithmetic Logic Unit (verified across `DATA_WIDTH = 8, 16, 32`)
2. **Synchronous FIFO (`dut/sync_fifo.v`)**: Arbitrary Depth Circular Buffer (verified across `DEPTH = 1, 5, 16`)
3. **UART Transmitter (`dut/uart_tx.v`)**: Configurable Baud Rate Serializer with Latched Parity, Reserved Mode `2'b11` Handling, and Cycle-Accurate Handshaking

All testbenches were built with negative-edge input driving and delta-delayed sampling to eliminate simulator race conditions. Automated verification in `scripts/verify.py` features sandboxed candidate pre-validation, exception-safe rollback mechanisms, and project-relative portable artifact reporting.

---

## 2. RTL Bug Analysis & Engineering Fixes

### 2.1 Arithmetic Logic Unit (`dut/alu.v`)
- **Identified Defect:** Subtraction underflow/borrow generation exhibited ambiguity between zero-extended arithmetic and reference model conventions.
- **Implemented Fix:**
  - Standardized borrow flag definition explicitly:
    ```verilog
    carry = (a < b); // Borrow flag: 1 on unsigned underflow, 0 otherwise
    ```
  - Parameterized `DATA_WIDTH` with clean zero-extension and zero flag evaluation:
    ```verilog
    assign zero = (result == {DATA_WIDTH{1'b0}});
    ```
  - Verified across 8-bit, 16-bit, and 32-bit instantiations with width-independent reference calculations.

### 2.2 Synchronous FIFO (`dut/sync_fifo.v`)
- **Identified Defects:**
  1. Boundary collision when simultaneous read and write occurred on an empty FIFO.
  2. Boundary collision when simultaneous read and write occurred on a full FIFO.
  3. Pointer wrap-around assumed power-of-two depths and failed on arbitrary depths (such as `DEPTH=5`).
  4. Lacked safe parameterization for minimal single-word buffers (`DEPTH=1`), causing zero-width vector evaluation and negative range indexes (`[-1:0]`).
- **Implemented Fix:**
  - Guaranteed safe parameter support for `DEPTH >= 1`:
    ```verilog
    localparam ADDR_WIDTH  = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam COUNT_WIDTH = $clog2(DEPTH < 2 ? 2 : DEPTH) + 1;
    ```
  - Standardized boundary collision behavior:
    - On **empty** (`count == 0`): Write succeeds, read flags underflow, count becomes 1.
    - On **full** (`count == DEPTH`): Read succeeds, write flags overflow, count becomes `DEPTH - 1`.
  - Replaced power-of-two bitmask indexing with modulo wrap-around pointer arithmetic:
    ```verilog
    wr_ptr <= (wr_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
    rd_ptr <= (rd_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;
    ```

### 2.3 UART Transmitter (`dut/uart_tx.v`)
- **Identified Defects:**
  1. Premature stop-bit termination (`clk_count < 2` instead of `CLKS_PER_BIT - 1`).
  2. One-cycle phase lag on `tx` line during state transitions to `STATE_PARITY` and `STATE_STOP`.
  3. Parity mode was sampled directly from the external wire in `STATE_DATA`, leaving transmissions vulnerable to midway pin changes.
  4. Unsupported parity mode `2'b11` was undefined and erroneously attempted to enter parity state.
- **Implemented Fix:**
  - Latched `parity_mode` synchronously into `tx_parity_mode` upon `tx_start` acceptance.
  - Defined behavior for reserved/unsupported `parity_mode == 2'b11` to safely bypass parity state (treated as No Parity) to prevent framing corruption.
  - Restored full stop-bit duration: `if (clk_count < CLKS_PER_BIT - 1)`.
  - Driven `tx` directly upon entering `STATE_STOP` and `STATE_PARITY` to guarantee immediate bit driving on state entry.
  - Cleared `tx_busy <= 1'b0` and asserted single-cycle `tx_done <= 1'b1` upon completion, returning to LOW on the immediate next clock cycle.

---

## 3. Verification Environment & Testbench Architecture

### 3.1 Elimination of Clock-Edge Race Conditions
All testbenches drive inputs on negative clock edges (`@(negedge clk)`) and sample outputs mid-cycle or on positive edges with explicit non-zero delta delay (`@(posedge clk); #1;`).

### 3.2 Reference Models & Test Suites
- **ALU (`testbenches/tb_alu.v`):**
  - **`DATA_WIDTH = 8`**: Directed nominals, corner boundaries (overflow, underflow borrow, double max), and 200 width-independent randomized vectors.
  - **`DATA_WIDTH = 16`**: 16-bit directed operations, corner cases, and 200 width-independent randomized vectors.
  - **`DATA_WIDTH = 32`**: 32-bit directed operations, corner cases, and 200 width-independent randomized vectors.
  - Total 600+ randomized vectors verified against parameterized golden reference calculations.
- **Synchronous FIFO (`testbenches/tb_sync_fifo.v`):**
  - **`DEPTH=1` (Minimal Single-Word):** Tested single write to full, single read to empty, write on full overflow, read on empty underflow, and empty/full simultaneous collisions.
  - **`DEPTH=5` (Non-Power-of-Two):** Tested pointer wrap-around (`0 -> 1 -> 2 -> 3 -> 4 -> 0`), overflow at 5, and multi-cycle circular operations.
  - **`DEPTH=16` (Deep FIFO):** Directed nominal, boundary limits, and 500-cycle randomized stress testing against independent shadow queue model.
- **UART Transmitter (`testbenches/tb_uart_tx.v`):**
  - **Single-Cycle `tx_done` Deassertion:** Verified that `tx_done` pulses for exactly 1 clock cycle and returns LOW on the immediate next clock edge.
  - **Inter-Frame Timing Measurement:** Measured actual line idle gap between consecutive transmissions (measured as 1 clock cycle).
  - **Parity Latching Test:** External `parity_mode` changed midway through data bit transmission; verified frame completed using originally latched mode.
  - **Unsupported Mode `2'b11`:** Tested and verified that `parity_mode = 2'b11` correctly transmits with no parity bit.
  - **Constrained-Random Testing:** 30 random frames across all parity modes.

---

## 4. Measured Verification Results

All tests executed with Icarus Verilog v12 and VVP:

```
=================================================================
 STARTING REGRESSION SUITE (3 Modules Found) 
=================================================================
[PASS] alu.v        : 0 Errors (WIDTH=8, WIDTH=16, WIDTH=32 + 600 Vectors)
[PASS] sync_fifo.v  : 0 Errors (DEPTH=1, DEPTH=5, DEPTH=16 + 500 Cycles)
[PASS] uart_tx.v    : 0 Errors (Parity Latch + Mode 2'b11 + 1-Cycle Gap + 30 Frames)
=================================================================
Overall Pass Rate: 100.0% (3/3 Passed, 0 Failed)
Regression Duration: ~4.5 seconds
```

---

## 5. Automated Verification Tooling (`scripts/verify.py`)

- **Deterministic Offline Verification:** `--no-ai` flag runs 100% locally with zero external network packages or API keys required.
- **Exception-Safe Rollback:** Candidate application is wrapped in a `try...finally` block; in the event of compilation failure, simulation failure, timeout, or unexpected exception, the original validated RTL is guaranteed to be restored from backup.
- **Sandbox Candidate Pre-Validation:** AI candidate fixes are compiled and simulated in isolation before touching validated RTL.
- **Strict Relative Paths:** All dashboard and waveform links use project-relative paths (`logs/*.vcd`), ensuring portability across operating systems and CI environments.
- **GitHub Actions CI:** Fully automated workflow in `.github/workflows/verify.yml` with zero mandatory external Python dependencies.
