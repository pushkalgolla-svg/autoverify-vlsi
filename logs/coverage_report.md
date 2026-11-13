# AutoVerify-VLSI: Unified Functional Coverage & Assertion Audit Report

**Date:** Generated Automatically by AutoVerify-VLSI Regression  
**Primary Simulator:** Icarus Verilog (`iverilog -g2012`), VVP runtime  
**Verification Methodology:** Portable Procedural Assertions & Explicit Binned Functional Coverage (Verilog-2012)  
*(Note: To maintain 100% open-source toolchain portability, this framework does not use proprietary UVM or SystemVerilog formal tools).*

---

## 1. Executive Regression Coverage Summary

- **Total Functional Coverage:** **`100.0%`** (119 / 119 Bins Covered)
- **Total Assertions / Checks Executed:** **`25,624`**
- **Passed Checks:** **`25,624`** (100.0%)
- **Failed Checks:** **`0`** (0.0%)
- **Status:** **🟢 ALL COVERAGE GOALS MET (0 Uncovered Bins)**

---

## 2. Per-Module Coverage & Assertion Audit

| Module | Status | Total Checks | Passed Checks | Failed Checks | Coverage Bins | Covered Bins | Coverage % | Uncovered Bins |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **alu** | ✅ PASSED | 1,917 | 1,917 | 0 | 42 | 42 | **100.0%** | None (100.0% Coverage Achieved) |
| **sync_fifo** | ✅ PASSED | 13,490 | 13,490 | 0 | 46 | 46 | **100.0%** | None (100.0% Coverage Achieved) |
| **uart_tx** | ✅ PASSED | 10,217 | 10,217 | 0 | 31 | 31 | **100.0%** | None (100.0% Coverage Achieved) |

---

## 3. Granular Coverage Bin Breakdown by Module

### 3.1 `alu.v` Coverage Breakdown

- **Coverage Summary:** `42 / 42` bins hit (100.0%)
- **Assertion Checks:** `1,917 / 1,917` passed

| Coverage Domain / Category | Detailed Measurements & Bins Exercised |
| :--- | :--- |
| **8-bit Opcodes** | ADD=55, SUB=68, AND=46, OR=44 (4/4 hit) |
| **16-bit Opcodes** | ADD=51, SUB=67, AND=45, OR=50 (4/4 hit) |
| **32-bit Opcodes** | ADD=69, SUB=42, AND=48, OR=54 (4/4 hit) |
| **ADD Carry Bins** | 8b[no_c=33, c=22], 16b[no_c=24, c=27], 32b[no_c=39, c=30] (6/6 hit) |
| **SUB Borrow Bins** | 8b[no_b=37, b=31], 16b[no_b=37, b=30], 32b[no_b=21, b=21] (6/6 hit) |
| **Zero Flag Bins** | 8b[nz=206, z=7], 16b[nz=209, z=4], 32b[nz=210, z=3] (6/6 hit) |
| **Corner Combos** | 8b[min_min=1, max_max=2, min_max=1, max_min=1] |
| **Corner Combos** | 16b[min_min=1, max_max=2, min_max=1, max_min=1] |
| **Corner Combos** | 32b[min_min=1, max_max=2, min_max=1, max_min=1] |
| **Random Vectors** | 8b=213, 16b=213, 32b=213 (Total Vectors = 639) |

### 3.2 `sync_fifo.v` Coverage Breakdown

- **Coverage Summary:** `46 / 46` bins hit (100.0%)
- **Assertion Checks:** `13,490 / 13,490` passed

| Coverage Domain / Category | Detailed Measurements & Bins Exercised |
| :--- | :--- |
| **Depths Tested** | D=1 (1), D=5 (1), D=16 (1) (3/3 hit) |
| **Occupancy D=1** | Empty=1312, Full=8 (2/2 hit) |
| **Occupancy D=5** | Empty=1268, 1-item=16, Inter=26, 4-item=6, Full=4 (5/5 hit) |
| **Occupancy D=16** | Empty=188, 1-item=200, Inter=916, 15-item=10, Full=6 (5/5 hit) |
| **Op Modes D=1** | WR=2, RD=2, Simul=2 (3/3 hit) |
| **Op Modes D=5** | WR=14, RD=14, Simul=3 (3/3 hit) |
| **Op Modes D=16** | WR=172, RD=185, Simul=131 (3/3 hit) |
| **Simul Collisions** | D1[Empty=1, Full=1], D5[Empty=1, Inter=1, Full=1], D16[Empty=8, Inter=122, Full=1] (8/8 hit) |
| **Error Flags** | D1[ovf=2, unf=2], D5[ovf=2, unf=2], D16[ovf=2, unf=15] (6/6 hit) |
| **Pointer Wraps** | D1[wr=1, rd=1], D5[wr=1, rd=1], D16[wr=1, rd=1] (6/6 hit) |
| **Circular Bursts** | D=5 (1), D=16 (1) (2/2 hit) |

### 3.3 `uart_tx.v` Coverage Breakdown

- **Coverage Summary:** `31 / 31` bins hit (100.0%)
- **Assertion Checks:** `10,217 / 10,217` passed

| Coverage Domain / Category | Detailed Measurements & Bins Exercised |
| :--- | :--- |
| **Parity Modes** | None=15, Odd=15, Even=15, Reserved=7 (4/4 hit) |
| **Timing Checks** | Start=52, Data=52, Parity=30, Stop=52 (4/4 hit) |
| **Key Patterns** | 0x00=3, 0xFF=1, 0x55=1, 0xAA=2, Walking1s(8/8 hit) |
| **Parity Latching** | Odd->None=1, Even->Odd=1 (2/2 hit) |
| **Busy Rejection** | Ignored tx_start during busy=1 (1/1 hit) |
| **Handshake Pulse** | BusyAssert=52, Exact1Pulse=52, ImmLowNext=1 (3/3 hit) |
| **Inter-Frame Gaps** | Delay0(1-clk)=1, Delay3(4-clk)=1, Delay7(8-clk)=1 (3/3 hit) |
| **Random Suite** | 30 Frames completed (1) (1/1 hit) |
| **Hardware Baud** | 115,200 Baud verified (1) (1/1 hit) |

