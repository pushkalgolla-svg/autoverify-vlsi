# AutoVerify-VLSI: Comprehensive Verification, Functional Coverage & Audit Report

**Date:** November 2026  
**Environment:** Icarus Verilog (`iverilog -g2012`), VVP runtime, GTKWave  
**Regression Status:** 🟢 **ALL 3 MODULES PASSED (0 ERRORS)**  
**Assertion Checks Executed:** 22,059 / 22,059 Passed (100.0%)  
**Functional Coverage:** 100.0% (118 / 118 Bins Covered)  
**Methodology:** Portable Procedural Assertions & Explicit Binned Functional Coverage (Verilog-2012)  
*(Note: To maintain 100% open-source toolchain portability, this framework does not use proprietary UVM or SystemVerilog formal tools).*

---

## 1. Executive Summary

This report documents the verification audit, root-cause bug isolation, functional coverage closure, and CI automation of the **AutoVerify-VLSI** digital IP portfolio:
1. **ALU (`dut/alu.v`)**: Parameterized Arithmetic Logic Unit (verified across `DATA_WIDTH = 8, 16, 32` with 1,917 checks and 42 coverage bins).
2. **Synchronous FIFO (`dut/sync_fifo.v`)**: Arbitrary Depth Circular Buffer (verified across `DEPTH = 1, 5, 16` with 13,407 checks and 46 coverage bins).
3. **UART Transmitter (`dut/uart_tx.v`)**: Serializer with Latched Parity, Protocol Frame Reconstruction, and Handshake Verification (6,735 checks and 30 coverage bins).

All testbenches drive inputs on negative clock edges (`@(negedge clk)`) and sample outputs post-NBA (`@(posedge clk); #1;`) to eliminate simulator race conditions.

---

## 2. RTL Bug Analysis & Engineering Fixes

### 2.1 Arithmetic Logic Unit (`dut/alu.v`)
- **Identified Defect:** Ambiguity in subtraction underflow / borrow flag generation between RTL and reference models.
- **Implemented Fix:**
  - Standardized explicit borrow flag semantics:
    ```verilog
    carry = (a < b); // Borrow flag: 1 on unsigned underflow, 0 otherwise
    ```
  - Parameterized `DATA_WIDTH` with clean zero flag evaluation:
    ```verilog
    zero = (result == {DATA_WIDTH{1'b0}});
    ```
  - Verified across 8, 16, and 32-bit instantiations with width-independent reference calculations.

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
  - Cleared `tx_busy <= 1'b0` and asserted single-cycle `tx_done <= 1'b1` upon completion, returning to LOW on the immediate next clock cycle.

---

## 3. Functional Coverage & Assertion Infrastructure

### 3.1 Assertion Architecture
All assertions are implemented as portable procedural checks evaluating post-NBA states (`@(posedge clk); #1;`):
- **ALU:** Assertions check `result`, `carry`, and `zero` cycle-by-cycle against a parameterized golden reference model.
- **Sync FIFO:** Assertions continuously check:
  - `count <= DEPTH`
  - `count >= 0`
  - `empty == (count == 0)`
  - `full == (count == DEPTH)`
  - Data integrity & ordering against independent cycle-accurate shadow queue models.
- **UART TX:** Assertions check bit-for-bit serial payload, bit duration timing (`CLKS_PER_BIT`), start/parity/stop bit compliance, and handshake timing.

### 3.2 Coverage Bin Breakdown (118 Total Bins)

| Module | Category | Bins | Details |
| :--- | :--- | :---: | :--- |
| **ALU** | Opcodes (8b, 16b, 32b) | 12 | ADD, SUB, AND, OR exercised across all 3 bitwidths |
| | Carry / Overflow (8b, 16b, 32b) | 6 | No-carry and carry asserted per bitwidth |
| | Borrow / Underflow (8b, 16b, 32b) | 6 | No-borrow and borrow asserted per bitwidth |
| | Zero Flag (8b, 16b, 32b) | 6 | Zero and non-zero results per bitwidth |
| | Extremum Corners (8b, 16b, 32b) | 12 | MIN_MIN, MAX_MAX, MIN_MAX, MAX_MIN combinations |
| **FIFO** | Depths Tested | 3 | DEPTH=1, DEPTH=5, DEPTH=16 |
| | Occupancy Boundaries | 12 | Empty, 1-item, intermediate, almost full, full |
| | Operation Modes | 9 | Write-only, Read-only, Simultaneous R/W across all 3 depths |
| | Simultaneous Collisions | 8 | Empty collisions, Full collisions, Intermediate collisions |
| | Error Flags | 6 | Overflow and underflow triggers across all 3 depths |
| | Pointer Wrap-Around | 6 | Write pointer wrap and Read pointer wrap across all 3 depths |
| | Circular Bursts | 2 | Sustained circular read/write bursts on DEPTH=5 and DEPTH=16 |
| **UART** | Parity Modes | 4 | None (`2'b00`), Odd (`2'b01`), Even (`2'b10`), Reserved (`2'b11`) |
| | Framing Bit Timing | 4 | Start bit, Data bits, Parity bit, Stop bit timing |
| | Data Patterns | 12 | All-0s, All-1s, Alt 0x55, Alt 0xAA, Walking-1s across 8 bit positions |
| | Parity Latching | 2 | Midway pin changes during transmission (Odd->None, Even->Odd) |
| | Busy Rejection | 1 | Request rejected while active frame transmitting |
| | Handshake Pulses | 3 | Busy active, single-cycle done pulse, immediate low next clock |
| | Inter-Frame Gaps | 3 | Measured gaps across delay 0 (1-clk), delay 3 (4-clk), delay 7 (8-clk) |
| | Stress Testing | 1 | 30 random frames across all configurations |
| **TOTAL** | — | **118** | **118 / 118 Bins Hit (100.0% Functional Coverage)** |

---

## 4. Measured Verification Results

All tests executed with Icarus Verilog v12 and VVP:

```
=================================================================
 STARTING REGRESSION SUITE (3 Modules Found) 
=================================================================
[PASS] alu.v        : 0 Errors | 1,917 Checks | 100.0% Coverage (42/42 Bins)
[PASS] sync_fifo.v  : 0 Errors | 13,407 Checks | 100.0% Coverage (46/46 Bins)
[PASS] uart_tx.v    : 0 Errors | 6,735 Checks  | 100.0% Coverage (30/30 Bins)
=================================================================
Overall Pass Rate: 100.0% (3/3 Passed, 0 Failed)
Total Assertions: 22,059 Checks (100.0% Passed)
Total Functional Coverage: 118 / 118 Bins (100.0%)
Regression Duration: ~4.5 seconds
```

---

## 5. AI Self-Healing Workflow & Safety Guardrails

The framework provides an optional, credible AI-assisted repair capability:
- **Isolated Demonstration Module:** Located in `examples/faulty_rtl/alu_faulty.v` with an injected borrow flag defect.
- **Demonstration Driver (`scripts/demo_ai_healing.py`):**
  - Identifies failure with simulation logs.
  - Generates diagnostic analysis and candidate fix (`examples/faulty_rtl/alu_candidate.v`).
  - Produces unified patch diff (`examples/faulty_rtl/alu_healing_patch.diff`).
  - Pre-validates candidate in a separate sandbox simulation.
  - Operates deterministically offline when no API key is available.
- **Production Guardrails:**
  - Original validated RTL (`dut/alu.v`) remains 100% untouched.
  - Candidate fixes are never automatically promoted without explicit engineering approval.
