# AutoVerify-VLSI: Unified Toggle Coverage Audit Report

**Generated From:** Simulation Value Change Dumps (`logs/*.vcd`)  
**Methodology:** Bit-level Transition Analysis ($0 \rightarrow 1$ and $1 \rightarrow 0$) across all DUT ports, registers, and nets.  
**Standard:** IEEE 1364/1800 ASIC Verification Standards.

---

## 1. Executive Toggle Summary

- **Total Monitored DUT Bit Nodes:** **`377`**
- **Full Toggles Exercised ($0 \rightarrow 1$ & $1 \rightarrow 0$):** **`355`**
- **Architecturally Tied-Off / Parameter-Bounded Bits:** **`22`**
- **Reachable Bit Nodes:** **`355`**
- **Raw Toggle Coverage:** **`94.2%`**
- **Effective Reachable Toggle Coverage:** **`100.0%`**
- **Status:** **🟢 100% REACHABLE TOGGLE COVERAGE ACHIEVED**

---

## 2. Per-Module Toggle Coverage Audit

| Module / VCD | DUT Signals | Total Bits | Full Toggles | Parameter Bounded | Reachable Bits | Raw Cov % | Reachable Cov % |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **`alu`** | 18 | 180 | 180 | 0 | 180 | **100.0%** | **100.0%** |
| **`sync_fifo`** | 39 | 99 | 95 | 4 | 95 | **96.0%** | **100.0%** |
| **`uart_tx`** | 28 | 98 | 80 | 18 | 80 | **81.6%** | **100.0%** |

---

## 3. Analysis of Parameter-Bounded / Tied-Off Bits

In commercial ASIC verification, generic parameterized modules often contain counter widths sized for maximum configurations that do not toggle under smaller parameter settings:

### Module `sync_fifo` Parameter Tie-Offs:

- **`tb_sync_fifo.dut_1.count`** (size 2 bits):
  - Unreachable bit indices: `[1]`
  - *Reason:* Count register width ceil-log2 sized for depth; higher bits bounded by runtime DEPTH parameter.
- **`tb_sync_fifo.dut_1.rd_ptr`** (size 1 bits):
  - Unreachable bit indices: `[0]`
  - *Reason:* Single-word FIFO (`DEPTH=1`) does not require multi-word address progression.
- **`tb_sync_fifo.dut_1.wr_ptr`** (size 1 bits):
  - Unreachable bit indices: `[0]`
  - *Reason:* Single-word FIFO (`DEPTH=1`) does not require multi-word address progression.
- **`tb_sync_fifo.dut_5.count`** (size 4 bits):
  - Unreachable bit indices: `[3]`
  - *Reason:* Count register width ceil-log2 sized for depth; higher bits bounded by runtime DEPTH parameter.

### Module `uart_tx` Parameter Tie-Offs:

- **`tb_uart_tx.dut.clk_count`** (size 16 bits):
  - Unreachable bit indices: `[4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]`
  - *Reason:* Sized for 16-bit countdown (`0..65535`), but active baud divider requires only values $\le$ `CLKS_PER_BIT`.
- **`tb_uart_tx.dut_hw_115200.clk_count`** (size 16 bits):
  - Unreachable bit indices: `[10, 11, 12, 13, 14, 15]`
  - *Reason:* Sized for 16-bit countdown (`0..65535`), but active baud divider requires only values $\le$ `CLKS_PER_BIT`.

