# SystemVerilog IEEE 1800 Reference Coverage Tier

This directory provides production-grade, object-oriented **SystemVerilog IEEE 1800** functional coverage reference packages for commercial EDA environments (Synopsys VCS, Cadence Xcelium, Siemens Questa).

---

## 1. Dual-Tier Verification Architecture

AutoVerify-VLSI employs an intentional **two-tier verification architecture** to bridge open-source continuous integration with commercial ASIC sign-off standards:

| Verification Tier | Location | Language / Standard | Target Simulators | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Tier 1: Portable CI** | `testbenches/tb_*.v` | Verilog-2012 Procedural Bins & Assertions | Icarus Verilog (`iverilog`), Verilator | Zero-dependency, offline open-source regression in GitHub Actions CI. |
| **Tier 2: Commercial Sign-Off** | `testbenches/systemverilog/*_coverage.sv` | IEEE 1800 `covergroup`, `coverpoint`, `cross`, `bins` | Synopsys VCS, Cadence Xcelium, Siemens Questa | UVM/OVM integration, commercial coverage database merging (UCDB/VDB), and formal sign-off. |

---

## 2. Included SystemVerilog Models

1. **`alu_coverage.sv` (`package alu_cov_pkg`)**:
   - Parameterized class `alu_coverage_model #(DATA_WIDTH)`.
   - `coverpoint op` covering all 4 opcodes (`ADD`, `SUB`, `AND`, `OR`).
   - `coverpoint a` and `coverpoint b` for zero, all-ones, MSB-only, LSB-only, and mid-range operands.
   - Comprehensive `cross_op_a_b` auditing arithmetic overflow, borrow, and logic boundaries.
   - Cross coverage for carry flag assertion and zero-result generation.

2. **`fifo_coverage.sv` (`package fifo_cov_pkg`)**:
   - Parameterized class `fifo_coverage_model #(DATA_WIDTH, DEPTH)`.
   - `coverpoint count` auditing empty (0), single-item (1), almost-full (DEPTH-1), full (DEPTH), and intermediate levels.
   - `cross_rw_occupancy` tracking simultaneous read/write collisions at empty, intermediate, and full boundaries.
   - Dedicated cross coverage for error flags: write on full (`overflow`) and read on empty (`underflow`).

3. **`uart_coverage.sv` (`package uart_cov_pkg`)**:
   - Class `uart_coverage_model`.
   - `cp_parity_mode` for all 4 parity modes (`NONE`, `ODD`, `EVEN`, `RESERVED`).
   - `cp_din` tracking walking ones, all-zeros, all-ones, and alternating patterns (`0x55`, `0xAA`).
   - Transition bins `(0 => 1 => 0)` auditing single-cycle `tx_done` pulses and active `tx_busy` frames.
   - `cross_busy_start` verifying rejection of start triggers while transmission is active.

---

## 3. Commercial EDA Invocation Examples

### Synopsys VCS
```bash
vcs -sverilog +v2k -timescale=1ns/1ps \
    +cover=bcest -cm line+tgl+fsm+branch+cond \
    dut/alu.v testbenches/systemverilog/alu_coverage.sv -o simv
./simv -cm line+tgl+fsm+branch+cond -cm_dir logs/vcs_cov.vdb
urg -dir logs/vcs_cov.vdb -format text
```

### Cadence Xcelium
```bash
xrun -sv -timescale 1ns/1ps -coverage all -covoverwrite \
    dut/sync_fifo.v testbenches/systemverilog/fifo_coverage.sv
imc -batch -run "load logs/cov_work/scope; report -detail -html"
```

### Siemens Questa / ModelSim
```bash
vlib work
vlog -sv dut/uart_tx.v testbenches/systemverilog/uart_coverage.sv
vsim -coverage -c work.uart_cov_pkg -do "coverage save -onexit logs/cov.ucdb; run -all; exit"
vcover report -details -html logs/cov.ucdb
```
