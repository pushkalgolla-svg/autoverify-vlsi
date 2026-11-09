# AutoVerify-VLSI: Automated RTL Verification & Self-Healing Framework

AutoVerify-VLSI is an automated digital design verification framework that bridges open-source electronic design automation (EDA) tools—**Icarus Verilog (`iverilog`)**, **VVP**, and **GTKWave**—with optional LLM orchestration using the **Google Gemini API**.

The framework provides robust, self-checking directed and constrained-random verification suites, cycle-accurate assertion checks, automated regression reporting, and isolated candidate patch synthesis for digital RTL IP cores.

---

## 📦 Verified RTL Cores

| IP Module | Location | Testbench | Key Verification Features |
| :--- | :--- | :--- | :--- |
| **ALU** | `dut/alu.v` | `testbenches/tb_alu.v` | Parameterized bitwidth, arithmetic overflow/underflow, standardized subtraction borrow flag `(a < b)`, zero flag, and 500-vector randomized stress test. |
| **Sync FIFO** | `dut/sync_fifo.v` | `testbenches/tb_sync_fifo.v` | Arbitrary `DEPTH` circular pointer wrapping, boundary collision handling (simultaneous R/W on empty and full), overflow/underflow protection, shadow queue reference model, and 500 random operations. |
| **UART TX** | `dut/uart_tx.v` | `testbenches/tb_uart_tx.v` | Configurable `CLKS_PER_BIT`, all parity modes (None, Odd, Even), full-duration stop-bit holding, back-to-back zero-idle transmissions, and cycle-by-cycle frame checks. |

---

## 🛠️ Tool Requirements & Prerequisites

### 1. EDA Simulator & Waveform Viewer
- **Icarus Verilog (`iverilog`) & VVP (`vvp`)**
  - **Ubuntu / Debian:**
    ```bash
    sudo apt-get update && sudo apt-get install -y iverilog gtkwave
    ```
  - **Windows (winget):**
    ```powershell
    winget install Icarus.Verilog
    ```
    *Ensure `iverilog` and `vvp` are accessible on your system `PATH`.*
- **GTKWave**: Used for visual signal timing and transition verification.

### 2. Python Environment
- Python `>= 3.10`
- Package manager: [`uv`](https://docs.astral.sh/uv/) (recommended) or standard `pip`.

---

## 🚀 Execution Commands

### 1. Run Complete Offline Regression (No API Key Required)
Run automated verification across all RTL modules using validated, committed self-checking testbenches:
```bash
# Using uv:
uv run python scripts/verify.py --regression --no-ai

# Or with standard Python:
python scripts/verify.py --regression --no-ai
```
*Exit code: `0` if all tests pass; `1` if any test fails (ideal for CI/CD).*

### 2. Run Verification on a Single Module
```bash
# Verify ALU
python scripts/verify.py --dut dut/alu.v --no-ai

# Verify Synchronous FIFO
python scripts/verify.py --dut dut/sync_fifo.v --no-ai

# Verify UART Transmitter
python scripts/verify.py --dut dut/uart_tx.v --no-ai
```

### 3. Inspect Waveforms in GTKWave
All testbenches generate portable VCD dumps in `logs/`:
```bash
gtkwave logs/alu.vcd
gtkwave logs/sync_fifo.vcd
gtkwave logs/uart_tx.vcd
```

### 4. Optional: Run with Gemini AI Diagnostics & Self-Healing
To enable AI testbench generation, root-cause log analysis, or candidate patch generation:
1. Configure your API key in `.env`:
   ```env
   GEMINI_API_KEY=your_gemini_api_key_here
   ```
2. Run with AI diagnostics:
   ```bash
   python scripts/verify.py --dut dut/alu.v
   ```
3. Run with candidate patch isolation:
   ```bash
   python scripts/verify.py --dut dut/sync_fifo.v --auto-heal
   ```
   *Note: AI-generated fixes are isolated to `dut/<module>_candidate.v` and `logs/<module>_patch.diff` for review. Existing validated RTL is never overwritten without the explicit `--apply-candidate` flag.*

---

## 📊 Verification Artifacts & Dashboards

Each regression run automatically produces clean, timestamped deliverables in `logs/`:
- `logs/regression_dashboard.md`: Markdown summary table with module status and error tallies.
- `logs/regression_dashboard.html`: Modern, shareable HTML regression report.
- `logs/<module>_sim.log`: Full raw simulation outputs with cycle timestamps.
- `logs/<module>.vcd`: Signal transition traces for GTKWave debugging.

---

## 🔄 Continuous Integration (CI)

Automated verification is configured via GitHub Actions in [`.github/workflows/verify.yml`](.github/workflows/verify.yml).  
On every push and pull request to `main`, the workflow:
1. Provisions Ubuntu environment and installs `iverilog`.
2. Runs `python scripts/verify.py --regression --no-ai`.
3. Verifies exit codes and uploads regression dashboards and VCD waveforms as build artifacts.
