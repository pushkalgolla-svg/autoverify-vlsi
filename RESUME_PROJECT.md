# AutoVerify-VLSI: Automated RTL Verification & Diagnostic Framework

An automated digital EDA verification platform pairing **Icarus Verilog (`iverilog`)**, **VVP**, and **GTKWave** with optional **Google Gemini API** orchestration for digital RTL IP cores (Arithmetic Logic Unit, Parameterized Synchronous FIFO, and UART Transmitter).

---

## 📄 Bullet Points for Your Resume

Copy-paste ready bullet points tailored for **ASIC / FPGA / Digital Design & Verification Engineer** roles (NVIDIA, Qualcomm, AMD, Apple, Intel, Synopsys, Cadence):

> * **Architected an Automated Digital Verification Framework** in Python integrating Icarus Verilog (`iverilog`), VVP, and GTKWave with optional Google Gemini LLM orchestration, enabling automated testbench synthesis, regression tracking, and failure triage across multiple digital IP cores.
> * **Designed Self-Checking Constrained-Random & Boundary Testbenches** with cycle-accurate reference models, explicit procedural coverage tracking, and automated VCD toggle coverage analysis, achieving 100% functional coverage (119/119 bins), 100% reachable toggle coverage, and executing 25,600+ assertion checks across ALU, Synchronous FIFO, and UART IP cores.
> * **Authored Dual-Tier Verification Models** providing portable Verilog-2012 procedural coverage/assertions for open-source CI alongside IEEE 1800 SystemVerilog reference packages (`covergroup`, `coverpoint`, `cross`) for commercial sign-off in Synopsys VCS, Cadence Xcelium, and Siemens Questa.
> * **Engineered an Automated Failure Diagnostic Pipeline** that parses simulation logs, classifies root causes between RTL logic faults and testbench specification discrepancies, and pre-validates isolated candidate patches in sandboxes before human review.
> * **Constructed Portable Verification & CI Automation** using GitHub Actions and Python, enforcing deterministic regression testing with zero testbench clock-edge race conditions, automated artifact cleanup, and unified HTML/Markdown coverage dashboard generation.

---

## 🎯 STAR Method Interview Cheat Sheet

When an interviewer asks: *"Tell me about a challenging or unique VLSI/hardware project you've worked on."*

### **Situation (Context)**
> *"In modern ASIC/VLSI design, functional verification consumes over 70% of the project schedule. Writing comprehensive testbenches that cover subtle boundary conditions—such as simultaneous read/write operations when a FIFO is full or empty, or stop-bit timing compliance in UART controllers—requires rigorous manual development and continuous regression monitoring."*

### **Task (Objective)**
> *"My goal was to build a reliable, automated verification environment that could run self-checking directed and constrained-random tests across multiple RTL modules, track explicit functional coverage bins, detect and isolate boundary bugs, generate signal waveforms for GTKWave inspection, and integrate with CI pipelines for automated regression tracking."*

### **Action (Implementation)**
> * *"I implemented **AutoVerify-VLSI**, a Python orchestrator connecting local EDA tools (`iverilog`, `vvp`, `gtkwave`) with optional LLM diagnostic capabilities."*
> * *"I hardened three digital IP cores and their self-checking testbenches:
>   1. **ALU (`dut/alu.v`)**: Verified across 8, 16, and 32-bit parameterized configurations with width-independent randomized stimulus and reference calculations, resolved subtraction borrow/underflow conventions `(a < b)` between RTL and golden models, and tracked 42 functional coverage bins across 1,900+ checks (100% toggle coverage).
>   2. **Synchronous FIFO (`dut/sync_fifo.v`)**: Handled arbitrary `DEPTH` pointer wrapping (including DEPTH=1, DEPTH=5, and DEPTH=16), fixed simultaneous read/write race conditions on empty and full boundaries, tracked 46 coverage bins across 13,490 checks, and integrated shadow queue reference verification (100% reachable toggle coverage).
>   3. **UART Transmitter (`dut/uart_tx.v`)**: Corrected premature stop-bit termination, latched parity configuration on transmission start, defined unsupported parity modes (`2'b11`), eliminated clock-edge race conditions, reconstructed serial frames bit-for-bit, verified real-world 115,200 Baud @ 100MHz clock (`CLKS_PER_BIT = 868`) cycle-accurately, and tracked 31 coverage bins across 10,200+ checks (100% reachable toggle coverage).*\"*
> * *\"I eliminated clock-edge race conditions in the testbenches by driving inputs on negative clock edges and sampling outputs with explicit delta delays after positive edges.\"*
> * *\"I built an automated VCD toggle coverage analyzer (`scripts/toggle_coverage.py`) that audits bit transitions, identifies parameter-tied bits, and reports 100% reachable coverage.\"*
> * *\"I designed a dual-tier verification architecture: portable Verilog-2012 procedural coverage for open-source CI, paired with production IEEE 1800 SystemVerilog reference covergroups in `testbenches/systemverilog/` for commercial EDA environments.\"*
> * *\"I established an automated regression runner (`scripts/verify.py`) with strict exit code validation, stale artifact elimination, watchdog timeouts, candidate patch isolation, and GitHub Actions CI automation.\"*

### **Result (Impact)**
> *\"Achieved 100% pass rates across all three IP cores with 100% functional coverage (119/119 bins covered across 25,624 assertion checks) and 100% reachable toggle coverage (355/355 bit nodes). Established an automated regression suite with full waveform generation and comprehensive HTML/Markdown summary reports, running deterministically in under 5 seconds.\"*

---

## 🏗️ System Architecture

```mermaid
flowchart TD
    A["RTL Design Under Test (DUT)<br/>dut/alu.v, sync_fifo.v, uart_tx.v"] --> B["Python Orchestrator<br/>(scripts/verify.py)"]
    TB["Validated Self-Checking Testbench<br/>(testbenches/tb_*.v)"] --> E
    B -->|Clean Stale Artifacts| C["Artifact Cleaner"]
    C --> E["Icarus Verilog Compiler<br/>(iverilog -g2012)"]
    A --> E
    E -->|Compilation Passed| G["Simulation Engine<br/>(vvp)"]
    G --> H["Signal Waveform Dump<br/>(logs/*.vcd -> GTKWave)"]
    G --> I["Simulation Output Log<br/>(logs/*_sim.log)"]
    I --> J{"All Assertions Passed?"}
    J -- "Yes (0 Errors)" --> K["🎉 Regression Passed (Exit Code 0)"]
    J -- "No (Errors Detected)" --> L["Failure Isolation & Exit Code 1"]
    L --> M{"AI Diagnostics Enabled?"}
    M -- "Yes" --> N["Gemini Root-Cause Diagnostic Report & Isolated Candidate Fix"]
    M -- "No (--no-ai)" --> P["Log Output & Deterministic Triage"]
    K --> Q["Automated Dashboard<br/>(logs/regression_dashboard.html/md)"]
    L --> Q
```

---

## 💻 Live Demo Commands (To show in an interview)

### 1. Run Complete Regression Suite (Offline / Deterministic):
```powershell
uv run python scripts/verify.py --regression --no-ai
```

### 2. Verify Individual IP Core:
```powershell
uv run python scripts/verify.py --dut dut/uart_tx.v --no-ai
```

### 3. Open Signal Waveforms in GTKWave:
```powershell
gtkwave logs/uart_tx.vcd
```

### 4. Run with Optional AI Root-Cause Diagnostic:
```powershell
uv run python scripts/verify.py --dut dut/alu.v
```
