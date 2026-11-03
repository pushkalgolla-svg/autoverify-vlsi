#!/usr/bin/env python3
"""
AutoVerify-VLSI: Autonomous LLM-Orchestrated Verification & Self-Healing Framework
Pairs Gemini API with Icarus Verilog (iverilog) & GTKWave for digital RTL IP cores.
"""

import os
import re
import sys
import shutil
import warnings
import argparse
import subprocess
from pathlib import Path

# Suppress deprecation/future warnings
warnings.filterwarnings("ignore")

# Force UTF-8 output on Windows consoles
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT_DIR = Path(__file__).resolve().parent.parent
DUT_DIR = ROOT_DIR / "dut"
TB_DIR = ROOT_DIR / "testbenches"
LOGS_DIR = ROOT_DIR / "logs"
ENV_FILE = ROOT_DIR / ".env"

def load_env():
    """Load GEMINI_API_KEY from .env if present."""
    if ENV_FILE.exists():
        with open(ENV_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, val = line.split("=", 1)
                    key = key.strip()
                    val = val.strip().strip("'\"")
                    if key and val and key not in os.environ:
                        os.environ[key] = val

def get_api_key():
    """Get Gemini API key from environment or .env."""
    load_env()
    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        print("\n" + "="*60)
        print(" [ERROR] GEMINI_API_KEY is not set.")
        print(f" Please add it to: {ENV_FILE}")
        print("="*60 + "\n")
        sys.exit(1)
    return api_key

def find_tool(tool_name):
    """Find binary on PATH or local fallback installation."""
    found = shutil.which(tool_name)
    if found:
        return found
    local_bin = Path(os.environ.get("USERPROFILE", "")) / "iverilog" / "bin" / f"{tool_name}.exe"
    if local_bin.exists():
        return str(local_bin)
    raise FileNotFoundError(f"Could not locate '{tool_name}'. Ensure Icarus Verilog is installed.")

def clean_code_block(text: str) -> str:
    """Extract code from markdown code fences or return raw text."""
    pattern = r"```(?:verilog|systemverilog)?\s*(.*?)\s*```"
    match = re.search(pattern, text, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()
    return text.strip()

def extract_corrected_code(analysis_text: str) -> str:
    """Extract full corrected Verilog code from Gemini's response."""
    blocks = re.findall(r"```(?:verilog|systemverilog)?\s*(.*?module\s+.*?\bendmodule)\s*```", analysis_text, re.DOTALL | re.IGNORECASE)
    if blocks:
        return blocks[-1].strip()
    return ""

def run_pipeline(dut_path: Path, model, auto_heal: bool, max_retries: int = 2):
    module_name = dut_path.stem
    tb_path = TB_DIR / f"tb_{module_name}.v"
    sim_bin = LOGS_DIR / f"{module_name}_sim.vvp"
    sim_log = LOGS_DIR / f"{module_name}_sim.log"
    vcd_path = LOGS_DIR / f"{module_name}.vcd"
    report_file = LOGS_DIR / f"{module_name}_report.md"

    TB_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)

    iverilog_bin = find_tool("iverilog")
    vvp_bin = find_tool("vvp")

    print("\n" + "=" * 65)
    print(f" AutoVerify-VLSI: Verifying Module [{dut_path.name}] ")
    print("=" * 65)

    with open(dut_path, "r", encoding="utf-8") as f:
        dut_code = f.read()

    # Step 1: Prompt Gemini for Testbench
    print(f"\n[1/4] Generating Constrained-Random & Corner-Case Testbench for {dut_path.name}...")
    prompt = f"""You are a Principal ASIC/FPGA Verification Engineer specializing in SystemVerilog.
Generate a comprehensive, self-checking Verilog/SystemVerilog testbench for the following Design Under Test (DUT).

DUT File: {dut_path.name}
```verilog
{dut_code}
```

Requirements for the testbench:
1. Target simulator: Icarus Verilog (`iverilog`).
   STRICT SYNTAX RULES for 100% Icarus Verilog compatibility:
   - Use standard Verilog-2001 syntax ONLY.
   - NEVER use C-style curly braces '{{' or '}}' for blocks, if-else, or loops! Always use 'begin' and 'end'. (Curly braces in Verilog are ONLY for concatenation like {{a, b}}).
   - Do NOT use SystemVerilog keywords (NO `logic`, NO `string` arguments in tasks, NO `automatic` tasks, NO classes, NO `$srandom`).
   - Use only standard `reg`, `wire`, and `integer`.
   - Declare internal test variables at the module level or at the top of initial blocks.
   - For random values, use `$random` or `$urandom`.
2. Instantiate the DUT with instance name `dut`.
3. Include a clock generator (`always #5 clk = ~clk;`) and proper synchronous active-low reset initialization if sequential.
4. Comprehensive test scenarios:
   - Reset verification and default state check.
   - Directed nominal tests covering all modes/opcodes/operations.
   - Corner cases and edge conditions (e.g. boundary values, overflow/underflow, simultaneous operations).
   - Constrained-random stress testing using randomized loops if applicable.
5. In each test case:
   - Self-check expected results against DUT outputs.
   - Print `[PASS] <description>` when matching.
   - Print `[FAIL] <description> Expected: ... Got: ...` on mismatch and increment `error_count`.
6. Enable VCD waveform dumping at the start of initial block:
   `$dumpfile("{vcd_path.as_posix()}"); $dumpvars(0, tb_{module_name});`
7. At completion:
   - If `error_count == 0`, display `ALL TESTS PASSED`.
   - If `error_count > 0`, display `SIMULATION FAILED: Total Errors = %0d` with error_count.
   - Call `$finish;` to terminate cleanly.
8. Output ONLY the Verilog code enclosed within a single ```verilog ``` markdown block.
"""

    response = model.generate_content(prompt)
    tb_code = clean_code_block(response.text)

    with open(tb_path, "w", encoding="utf-8") as f:
        f.write(tb_code)
    print(f"[1/4] Saved testbench to: {tb_path.name}")

    # Step 2: Compile with iverilog (with auto-fix retry if syntax error occurs)
    print(f"\n[2/4] Compiling design with Icarus Verilog (`iverilog -g2012`)...")
    compile_cmd = [iverilog_bin, "-g2012", "-o", str(sim_bin), str(dut_path), str(tb_path)]
    comp_result = subprocess.run(compile_cmd, capture_output=True, text=True)

    if comp_result.returncode != 0:
        print(f"[!] Compilation failed. Prompting Gemini to fix testbench syntax...")
        fix_tb_prompt = f"""The following testbench failed to compile with Icarus Verilog:
```verilog
{tb_code}
```
Compiler Error:
{comp_result.stderr}

Please fix the testbench for Icarus Verilog:
- NEVER use C-style curly braces '{{' or '}}' for blocks or loops; use 'begin' and 'end' ONLY.
- Ensure all variable declarations in tasks and functions are at the VERY BEGINNING of the task/function block before any statements.
- Return ONLY the complete corrected Verilog code in a ```verilog ``` block.
"""
        fixed_resp = model.generate_content(fix_tb_prompt)
        tb_code = clean_code_block(fixed_resp.text)
        with open(tb_path, "w", encoding="utf-8") as f:
            f.write(tb_code)
        
        comp_result = subprocess.run(compile_cmd, capture_output=True, text=True)
        if comp_result.returncode != 0:
            print(f"[ERROR] Compilation still failed after retry:\n{comp_result.stderr}")
            return False

    print("[2/4] Compilation passed!")

    # Step 3: Run simulation with vvp
    print(f"\n[3/4] Running simulation with vvp...")
    sim_cmd = [vvp_bin, str(sim_bin)]
    sim_result = subprocess.run(sim_cmd, capture_output=True, text=True)
    sim_output = sim_result.stdout + sim_result.stderr

    with open(sim_log, "w", encoding="utf-8") as f:
        f.write(sim_output)

    print("\n--- Simulation Output Highlights ---")
    lines = sim_output.strip().splitlines()
    for line in lines[:20]:
        print(line)
    if len(lines) > 20:
        print(f"... [{len(lines)-20} more lines in logs/{sim_log.name}]")
    print("------------------------------------\n")

    # Check if simulation failed to execute due to testbench error
    if "Program not runnable" in sim_output or "Error:" in sim_output and "[FAIL]" not in sim_output:
        print(f"[!] Testbench runtime error detected. Re-prompting Gemini to fix testbench...")
        fix_prompt = f"""The testbench produced a runtime simulator error in Icarus Verilog:
{sim_output}

Please fix the testbench:
- Do not use unsupported system tasks like $srandom. Use $random or $urandom.
- Ensure all variable declarations are at the top of tasks/functions.
- Return ONLY the corrected Verilog code in a ```verilog ``` block.
"""
        fixed_resp = model.generate_content(fix_prompt)
        tb_code = clean_code_block(fixed_resp.text)
        with open(tb_path, "w", encoding="utf-8") as f:
            f.write(tb_code)
        # Re-compile and re-run
        subprocess.run(compile_cmd, capture_output=True, text=True)
        sim_result = subprocess.run(sim_cmd, capture_output=True, text=True)
        sim_output = sim_result.stdout + sim_result.stderr
        with open(sim_log, "w", encoding="utf-8") as f:
            f.write(sim_output)

    # Step 4: Check for Failures & Feedback Loop
    has_failure = (
        "[FAIL]" in sim_output or
        "SIMULATION FAILED" in sim_output or
        "FAILED" in sim_output or
        sim_result.returncode != 0
    )

    if not has_failure:
        print(f"\n🎉 [SUCCESS] All verification tests passed for {dut_path.name}! (0 errors)")
        print(f"📊 Waveform dumped to: {vcd_path}")
        print(f"   View in GTKWave: gtkwave \"{vcd_path}\"")
        return True

    print(f"\n[4/4] ⚠️ Bugs detected during simulation! Engaging Gemini for Root-Cause Analysis...")
    analysis_prompt = f"""You are a Principal ASIC/FPGA Verification Engineer.
A Verilog simulation failed. Analyze the RTL, the testbench, and the simulation log to diagnose the bug.

=== RTL Source ({dut_path.name}) ===
{dut_code}

=== Testbench Source ({tb_path.name}) ===
{tb_code}

=== Simulation Log ===
{sim_output}

Please provide a structured report with:
1. Executive Summary: What failed in the simulation.
2. Root Cause Classification: State clearly whether the bug is in the **RTL Design** or in the **Testbench**.
3. Detailed Technical Explanation: Pinpoint exact lines and logical mechanics causing the failure.
4. Corrective Code Diff: Show the unified diff.
5. Corrected RTL Code: Provide the COMPLETE, bug-free `{dut_path.name}` enclosed in a ```verilog ``` block so it can be automatically applied.
"""

    analysis_response = model.generate_content(analysis_prompt)
    report_text = analysis_response.text

    with open(report_file, "w", encoding="utf-8") as f:
        f.write(report_text)

    print("\n" + "=" * 65)
    print(" GEMINI ROOT-CAUSE ANALYSIS & DIAGNOSTIC REPORT ")
    print("=" * 65)
    print(report_text)
    print("=" * 65)
    print(f"\nDiagnostic report saved to: {report_file}")

    # Autonomous Self-Healing Option
    if auto_heal:
        print(f"\n[SELF-HEALING] --auto-heal enabled. Extracting patch from Gemini...")
        fixed_code = extract_corrected_code(report_text)
        if fixed_code and max_retries > 0:
            backup_path = dut_path.with_suffix(".v.bak")
            shutil.copyfile(dut_path, backup_path)
            print(f"[SELF-HEALING] Backup created at: {backup_path.name}")
            with open(dut_path, "w", encoding="utf-8") as f:
                f.write(fixed_code)
            print(f"[SELF-HEALING] Applied fix to {dut_path.name}. Re-running verification...")
            return run_pipeline(dut_path, model, auto_heal=False, max_retries=max_retries-1)
        else:
            print("[SELF-HEALING] Could not extract complete corrected RTL module. Manual review recommended.")

    return False

def main():
    parser = argparse.ArgumentParser(description="AutoVerify-VLSI: Autonomous RTL Verification & Self-Healing Agent")
    parser.add_argument("--dut", type=str, default="dut/sync_fifo.v", help="Path to DUT Verilog file (default: dut/sync_fifo.v)")
    parser.add_argument("--auto-heal", action="store_true", help="Automatically patch RTL with Gemini's fix and re-verify")
    parser.add_argument("--model", type=str, default="gemini-2.5-flash", help="Gemini model name")
    args = parser.parse_args()

    api_key = get_api_key()
    try:
        import google.generativeai as genai
    except ImportError:
        print("[ERROR] 'google-generativeai' not installed.")
        sys.exit(1)

    genai.configure(api_key=api_key)
    model = genai.GenerativeModel(args.model)

    dut_path = Path(args.dut)
    if not dut_path.is_absolute():
        dut_path = ROOT_DIR / dut_path

    if not dut_path.exists():
        print(f"[ERROR] DUT file not found: {dut_path}")
        sys.exit(1)

    run_pipeline(dut_path, model, auto_heal=args.auto_heal)

if __name__ == "__main__":
    main()
