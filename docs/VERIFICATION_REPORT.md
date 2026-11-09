# AutoVerify-VLSI: Comprehensive Verification & Audit Report

**Date:** November 2026  
**Environment:** Icarus Verilog (`iverilog -g2012`), VVP runtime, GTKWave  
**Regression Status:** 🟢 **ALL 3 MODULES PASSED (0 ERRORS)**  
**Pass Rate:** 100.0% across 1,000+ directed, parameterized, and constrained-random cycles  

---

## 1. Executive Summary

This report documents the verification audit, root-cause bug isolation, and hardening of the **AutoVerify-VLSI** IP portfolio:
1. **ALU (`dut/alu.v`)**: Parameterized Arithmetic Logic Unit
2. **Synchronous FIFO (`dut/sync_fifo.v`)**: Arbitrary Depth Circular Buffer (tested across `DEPTH=1`, `DEPTH=5`, and `DEPTH=16`)
3. **UART Transmitter (`dut/uart_tx.v`)**: Configurable Baud Rate Serializer with Latched Parity & Cycle-Accurate Handshaking

All modules were audited for functional race conditions, boundary limit edge cases, reset behavior, and parity/framing compliance. Testbenches were re-engineered with negative-edge input driving and delta-delayed output sampling to eliminate simulator race conditions. Automated verification in `scripts/verify.py` was enhanced with isolated candidate sandbox validation, automatic backup/rollback, exit code validation, and GitHub Actions CI.

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
  3. Pointer wrap-around assumed power-of-two depths and failed on arbitrary depths (such as `DEPTH=5`).
  4. Lacked safe parameterization for minimal single-word buffers (`DEPTH=1`), causing zero-width vector evaluation and negative range indexes (`[-1:0]`).
- **Root Cause:**
  $clog2(1) evaluates to 0, causing pointer declarations `[ADDR_WIDTH-1:0]` to produce illegal reverse ranges. Count tracking failed to isolate simultaneous read and write events at capacity limits.
- **Implemented Fix:**
  - Guaranteed safe parameter support for `DEPTH >= 1`:
    ```verilog
    localparam ADDR_WIDTH  = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam COUNT_WIDTH = $clog2(DEPTH < 2 ? 2 : DEPTH) + 1;
    ```
  - Standardized boundary collision behavior:
    - On **empty** (`count == 0`): If both read and write occur, write succeeds, read fails (underflow flag pulses), and count becomes 1.
    - On **full** (`count == DEPTH`): If both read and write occur, read succeeds, write fails (overflow flag pulses), and count becomes `DEPTH - 1`.
  - Replaced power-of-two bitmask indexing with modulo wrap-around pointer arithmetic:
    ```verilog
    wr_ptr <= (wr_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
    rd_ptr <= (rd_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;
    ```
  - Tested across `DEPTH=1`, `DEPTH=5`, and `DEPTH=16`.

### 2.3 UART Transmitter (`dut/uart_tx.v`)
- **Identified Defects:**
  1. Premature stop-bit termination (`clk_count < 2` instead of `CLKS_PER_BIT - 1`).
  2. One-cycle phase lag on `tx` line during state transitions to `STATE_PARITY` and `STATE_STOP`.
  3. Parity mode was sampled directly from the external wire in `STATE_DATA`, making transmissions vulnerable to midway pin changes.
  4. `tx_busy` remained asserted or failed to clear synchronously on completion.
- **Root Cause:**
  Reading dynamic input `parity_mode` during FSM execution allowed external noise or multi-cycle changes to corrupt active frame structure. Updating `tx` sequentially inside states created a 1-cycle latency relative to baud counter boundaries.
- **Implemented Fix:**
  - Latched `parity_mode` synchronously into `tx_parity_mode` upon `tx_start` acceptance and maintained across the entire frame.
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
All testbenches drive inputs on negative clock edges (`@(negedge clk)`) and sample outputs mid-cycle or on positive edges with explicit non-zero delta delay (`@(posedge clk); #1;`).

### 3.2 Reference Models & Test Suites
- **ALU (`testbenches/tb_alu.v`):**
  - Directed nominal operations (ADD, SUB, AND, OR).
  - Boundary cases: arithmetic overflow, underflow borrow, and identity zero.
  - 500-vector constrained-random stress testing against behavioral golden model.
- **Synchronous FIFO (`testbenches/tb_sync_fifo.v`):**
  - **`DEPTH=1` (Minimal Single-Word):** Tested single write to full, single read to empty, write on full overflow, read on empty underflow, and empty/full simultaneous collisions.
  - **`DEPTH=5` (Non-Power-of-Two):** Tested pointer wrap-around (`0 -> 1 -> 2 -> 3 -> 4 -> 0`), overflow at 5, and multi-cycle circular operations.
  - **`DEPTH=16` (Deep FIFO):** Directed nominal, boundary limits, and 500-cycle randomized stress testing against independent shadow queue model.
- **UART Transmitter (`testbenches/tb_uart_tx.v`):**
  - **Parity Latching Test:** External `parity_mode` changed midway through data bit transmission; verified frame completed using originally latched mode.
  - **`tx_busy` Invariant:** Monitored across every clock cycle from start bit to stop bit completion.
  - **`tx_done` Pulse Verification:** Verified that `tx_done` asserts for exactly ONE clock cycle.
  - **Zero-Idle Consecutive Frames:** Back-to-back zero-idle transmissions verified with zero framing errors.
  - **Constrained-Random Testing:** 30 random frames across all parity modes.

---

## 4. Measured Verification Results

All tests executed with Icarus Verilog v12 and VVP:

```
=================================================================
 STARTING REGRESSION SUITE (3 Modules Found) 
=================================================================
[PASS] alu.v        : 0 Errors (Directed + 500 Random Vectors)
[PASS] sync_fifo.v  : 0 Errors (DEPTH=1, DEPTH=5, DEPTH=16 + 500 Cycles)
[PASS] uart_tx.v    : 0 Errors (Directed + Parity Latch + Handshake + 30 Frames)
=================================================================
Overall Pass Rate: 100.0% (3/3 Passed, 0 Failed)
Regression Duration: ~4.5 seconds
```

---

## 5. Automated Verification Tooling (`scripts/verify.py`)

- **Deterministic Offline Verification:** `--no-ai` flag runs 100% locally with zero external network packages or API keys required.
- **Sandbox Candidate Pre-Validation:** AI candidate fixes are compiled and simulated in isolation before touching validated RTL.
- **Automatic Rollback:** If a candidate application fails during live re-verification, the original RTL is automatically restored from backup.
- **Strict Relative Paths:** All dashboard and waveform links use project-relative paths (`logs/*.vcd`), ensuring portability across operating systems and CI environments.
- **GitHub Actions CI:** Fully automated workflow in `.github/workflows/verify.yml` with zero mandatory external Python dependencies.
