#!/usr/bin/env python3
"""
AutoVerify-VLSI: Automated RTL Verification & Diagnostic Framework
Pairs Icarus Verilog (iverilog) & GTKWave with optional Google Gemini API
for digital RTL IP cores (ALU, Parameterized Sync FIFO, UART Transmitter).
"""

import os
import re
import sys
import difflib
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
    """Load GEMINI_API_KEY from .env if present (standard library parser)."""
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

def get_api_key(required: bool = True):
    """Get Gemini API key from environment or .env file."""
    load_env()
    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key and required:
        print("\n" + "=" * 65)
        print(" [ERROR] GEMINI_API_KEY is not set.")
        print(f" To use AI features, add it to {ENV_FILE} or set as environment variable.")
        print(" To run verification locally without AI, use the '--no-ai' flag.")
        print("=" * 65 + "\n")
        sys.exit(1)
    return api_key

def find_tool(tool_name: str) -> str:
    """Find EDA binary on PATH or common local installation paths."""
    found = shutil.which(tool_name)
    if found:
        return found
    candidates = [
        Path(os.environ.get("USERPROFILE", "")) / "iverilog" / "bin" / f"{tool_name}.exe",
        Path("C:/iverilog/bin") / f"{tool_name}.exe",
        Path("C:/Program Files/iverilog/bin") / f"{tool_name}.exe",
    ]
    for cand in candidates:
        if cand.exists():
            return str(cand)
    raise FileNotFoundError(
        f"Could not locate required EDA tool '{tool_name}'.\n"
        "Please ensure Icarus Verilog is installed and added to PATH.\n"
        "Linux: sudo apt-get install -y iverilog\n"
        "Windows: winget install Icarus.Verilog (or add iverilog/bin to Path)"
    )

def clean_code_block(text: str) -> str:
    """Extract code from markdown code fences and sanitize invalid literals."""
    pattern = r"```(?:verilog|systemverilog)?\s*(.*?)\s*```"
    match = re.search(pattern, text, re.DOTALL | re.IGNORECASE)
    code = match.group(1).strip() if match else text.strip()

    def fix_binary_literal(m):
        width, digits = m.group(1), m.group(2)
        if all(c in '01xzXZ_' for c in digits):
            return m.group(0)
        return f"{width}'d{int(digits)}"

    code = re.sub(r"(\d+)'b([0-9]+)", fix_binary_literal, code)
    return code

def generate_with_fallback(prompt: str, preferred_model: str = "gemini-2.5-flash"):
    """Call Gemini API with automatic fallback across models on quota limits."""
    try:
        import google.generativeai as genai
    except ImportError:
        raise ImportError("Package 'google-generativeai' is required for AI features. Install with: pip install google-generativeai")

    model_candidates = [preferred_model, "gemini-2.5-flash", "gemini-2.5-flash-lite"]
    unique_models = []
    for m in model_candidates:
        if m not in unique_models:
            unique_models.append(m)

    last_error = None
    for m in unique_models:
        try:
            model = genai.GenerativeModel(m)
            return model.generate_content(prompt)
        except Exception as e:
            err_str = str(e)
            if "ResourceExhausted" in err_str or "429" in err_str or "quota" in err_str.lower():
                print(f"[!] Quota limit reached on {m}. Falling back to next available model...")
                last_error = e
                continue
            raise e
    raise last_error

def extract_corrected_code(analysis_text: str) -> str:
    """Extract full corrected Verilog module code from Gemini response."""
    blocks = re.findall(
        r"```(?:verilog|systemverilog)?\s*(module\s+.*?\bendmodule)\s*```",
        analysis_text,
        re.DOTALL | re.IGNORECASE
    )
    if blocks:
        return blocks[-1].strip()
    return ""

def remove_stale_artifacts(module_name: str):
    """Remove previous simulation executables, logs, and traces to prevent stale results."""
    stale_files = [
        LOGS_DIR / f"{module_name}_sim.vvp",
        LOGS_DIR / f"{module_name}_sim.log",
        LOGS_DIR / f"{module_name}.vcd",
        LOGS_DIR / f"{module_name}_candidate_sim.vvp",
        LOGS_DIR / f"{module_name}_candidate_sim.log",
    ]
    for f in stale_files:
        if f.exists():
            try:
                f.unlink()
            except OSError:
                pass

def test_candidate_in_isolation(candidate_path: Path, tb_path: Path, module_name: str, iverilog_bin: str, vvp_bin: str) -> tuple[bool, str]:
    """Compile and simulate candidate RTL in sandbox isolation before replacing original."""
    cand_bin = LOGS_DIR / f"{module_name}_candidate_sim.vvp"
    cand_log = LOGS_DIR / f"{module_name}_candidate_sim.log"

    if cand_bin.exists():
        try:
            cand_bin.unlink()
        except OSError:
            pass

    # 1. Compile candidate in sandbox
    compile_cmd = [iverilog_bin, "-g2012", "-o", str(cand_bin), str(candidate_path), str(tb_path)]
    try:
        comp_res = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        return False, "Candidate compilation timed out after 20 seconds."

    if comp_res.returncode != 0 or not cand_bin.exists():
        return False, f"Candidate compilation failed:\n{comp_res.stderr or comp_res.stdout}"

    # 2. Simulate candidate in sandbox
    try:
        sim_res = subprocess.run([vvp_bin, str(cand_bin)], capture_output=True, text=True, timeout=15)
        sim_out = sim_res.stdout + sim_res.stderr
        sim_code = sim_res.returncode
    except subprocess.TimeoutExpired:
        return False, "Candidate simulation timed out (15s): Possible infinite loop."
    finally:
        if cand_bin.exists():
            try:
                cand_bin.unlink()
            except OSError:
                pass

    with open(cand_log, "w", encoding="utf-8") as f:
        f.write(sim_out)

    has_fail = (
        sim_code != 0 or
        "[FAIL]" in sim_out or
        "[ERROR]" in sim_out or
        "SIMULATION FAILED" in sim_out or
        "ALL TESTS PASSED" not in sim_out
    )
    if has_fail:
        return False, f"Candidate failed verification checks (exit code {sim_code})."

    return True, "Candidate RTL passed all compilation and self-checking simulation checks (0 errors)."

def synthesize_testbench_ai(dut_path: Path, tb_path: Path, model_name: str) -> bool:
    """Synthesize testbench using Gemini API with strict Verilog-2001 constraints."""
    module_name = dut_path.stem
    with open(dut_path, "r", encoding="utf-8") as f:
        dut_code = f.read()

    print(f"\n[1/4] Generating Constrained-Random & Corner-Case Testbench for {dut_path.name}...")
    prompt = f"""You are a Principal ASIC/FPGA Verification Engineer specializing in SystemVerilog.
Generate a comprehensive, self-checking Verilog testbench for the following Design Under Test (DUT).

DUT File: {dut_path.name}
```verilog
{dut_code}
```

Requirements for the testbench:
1. Target simulator: Icarus Verilog (`iverilog`).
   STRICT SYNTAX RULES for 100% Icarus Verilog compatibility:
   - Use standard Verilog-2001 syntax ONLY.
   - NEVER use C-style curly braces '{{' or '}}' for blocks, if-else, or loops! Always use 'begin' and 'end'.
   - Do NOT use SystemVerilog keywords (NO `logic`, NO `string` arguments in tasks, NO classes).
   - Use only standard `reg`, `wire`, and `integer`.
   - Declare internal test variables at module level or top of blocks.
   - For random values, use `$random` or `$urandom`.
   - Ensure all binary literals ('b) contain only 0 and 1.
   - MANDATORY WATCHDOG: Always include a safety watchdog timer to prevent infinite hangs:
     `initial begin #5000000; $display("[ERROR] Watchdog timeout: simulation hung!"); $finish; end`
   - AVOID RACE CONDITIONS: Drive sequential inputs on `@(negedge clk)` and sample DUT outputs at `@(posedge clk)` with `#1` delay or at `@(negedge clk)`.
2. Instantiate the DUT with instance name `dut`.
3. Include clock generator (`always #5 clk = ~clk;`) and synchronous/asynchronous reset initialization.
4. Comprehensive test scenarios:
   - Reset state verification.
   - Directed nominal tests covering all operations.
   - Corner cases and edge conditions (overflow, underflow, boundary limits).
   - Constrained-random stress testing.
5. In each test case:
   - Self-check expected results against DUT outputs.
   - Print `[PASS] <description>` when matching.
   - Print `[FAIL] <description> Expected: ... Got: ...` on mismatch and increment `error_count`.
6. Enable VCD waveform dumping using portable relative path:
   `$dumpfile("logs/{module_name}.vcd"); $dumpvars(0, tb_{module_name});`
7. At completion:
   - If `error_count == 0`, display `ALL TESTS PASSED`.
   - If `error_count > 0`, display `SIMULATION FAILED: Total Errors = %0d` with error_count.
   - Call `$finish;` to terminate cleanly.
8. Output ONLY the Verilog code enclosed within a single ```verilog ``` block.
"""
    try:
        response = generate_with_fallback(prompt, preferred_model=model_name)
        tb_code = clean_code_block(response.text)
        with open(tb_path, "w", encoding="utf-8") as f:
            f.write(tb_code)
        print(f"[1/4] Saved AI-generated testbench to: {tb_path.name}")
        return True
    except Exception as e:
        print(f"[ERROR] AI testbench generation failed: {e}")
        return False

def run_pipeline(
    dut_path: Path,
    no_ai: bool = False,
    regen_tb: bool = False,
    model_name: str = "gemini-2.5-flash",
    auto_heal: bool = False,
    apply_candidate: bool = False
) -> bool:
    """Run full verification pipeline on a single DUT."""
    module_name = dut_path.stem
    tb_path = TB_DIR / f"tb_{module_name}.v"
    sim_bin = LOGS_DIR / f"{module_name}_sim.vvp"
    sim_log = LOGS_DIR / f"{module_name}_sim.log"
    vcd_path = LOGS_DIR / f"{module_name}.vcd"
    report_file = LOGS_DIR / f"{module_name}_report.md"

    TB_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)

    # 0. Clean stale compilation and simulation artifacts
    remove_stale_artifacts(module_name)

    iverilog_bin = find_tool("iverilog")
    vvp_bin = find_tool("vvp")

    print("\n" + "=" * 65)
    print(f" AutoVerify-VLSI: Verifying Module [{dut_path.name}] ")
    print("=" * 65)

    # 1. Obtain Testbench
    if not tb_path.exists() or regen_tb:
        if no_ai:
            if not tb_path.exists():
                print(f"[ERROR] Testbench '{tb_path.name}' not found and '--no-ai' is specified.")
                print(f"Please provide '{tb_path}' or run without '--no-ai' to synthesize one.")
                return False
        else:
            success = synthesize_testbench_ai(dut_path, tb_path, model_name)
            if not success and not tb_path.exists():
                return False
    else:
        print(f"[1/4] Using validated testbench: testbenches/{tb_path.name}")

    # 2. Compile Design
    print(f"\n[2/4] Compiling design with Icarus Verilog (`iverilog -g2012`)...")
    compile_cmd = [iverilog_bin, "-g2012", "-o", str(sim_bin), str(dut_path), str(tb_path)]
    try:
        comp_result = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        print("[ERROR] Compilation timed out after 20 seconds.")
        return False

    if comp_result.returncode != 0 or not sim_bin.exists():
        print(f"[ERROR] Compilation failed (exit code {comp_result.returncode}):")
        print(comp_result.stderr or comp_result.stdout)
        return False

    print("[2/4] Compilation passed!")

    # 3. Run Simulation
    print(f"\n[3/4] Running simulation with vvp...")
    sim_cmd = [vvp_bin, str(sim_bin)]
    timed_out = False
    try:
        sim_result = subprocess.run(sim_cmd, capture_output=True, text=True, timeout=15)
        sim_output = sim_result.stdout + sim_result.stderr
        sim_code = sim_result.returncode
    except subprocess.TimeoutExpired as e:
        timed_out = True
        sim_output = (e.stdout or "") + (e.stderr or "") + "\n[ERROR] Simulation timed out (15s): Watchdog or deadlock triggered."
        sim_code = 1

    with open(sim_log, "w", encoding="utf-8") as f:
        f.write(sim_output)

    print("\n--- Simulation Output Highlights ---")
    lines = sim_output.strip().splitlines()
    for line in lines[:25]:
        print(line)
    if len(lines) > 25:
        print(f"... [{len(lines)-25} more lines in logs/{sim_log.name}]")
    print("------------------------------------\n")

    # 4. Check for Failures & Exit Codes
    error_count = 0
    err_matches = re.findall(r"Total Errors\s*=\s*(\d+)", sim_output)
    if err_matches:
        error_count = int(err_matches[-1])

    has_failure = (
        error_count > 0 or
        sim_code != 0 or
        timed_out or
        "[FAIL]" in sim_output or
        "[ERROR]" in sim_output or
        "SIMULATION FAILED" in sim_output or
        "ALL TESTS PASSED" not in sim_output
    )

    if not has_failure:
        print(f"🎉 [SUCCESS] All verification tests passed for {dut_path.name}! (0 errors)")
        if vcd_path.exists():
            print(f"📊 Waveform dumped to: logs/{vcd_path.name}")
            print(f"   View in GTKWave: gtkwave logs/{vcd_path.name}")
        return True

    print(f"\n[4/4] ⚠️ Failure detected in {dut_path.name}!")
    print(f"      Exit code: {sim_code} | Total recorded errors: {error_count or 'N/A'}")

    if no_ai:
        print("[INFO] AI diagnostic skipped ('--no-ai' flag active).")
        return False

    # Optional AI Diagnostic Analysis
    api_key = get_api_key(required=False)
    if not api_key:
        print("[INFO] GEMINI_API_KEY not set. Skipping AI root-cause diagnostics.")
        return False

    with open(dut_path, "r", encoding="utf-8") as f:
        dut_code = f.read()
    with open(tb_path, "r", encoding="utf-8") as f:
        tb_code = f.read()

    print("\n[AI DIAGNOSTICS] Engaging Gemini for Root-Cause Analysis...")
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
5. Corrected RTL Code: Provide the COMPLETE, bug-free `{dut_path.name}` enclosed in a ```verilog ``` block.
"""
    try:
        analysis_response = generate_with_fallback(analysis_prompt, preferred_model=model_name)
        report_text = analysis_response.text
        with open(report_file, "w", encoding="utf-8") as f:
            f.write(report_text)

        print("\n" + "=" * 65)
        print(" GEMINI ROOT-CAUSE ANALYSIS & DIAGNOSTIC REPORT ")
        print("=" * 65)
        print(report_text)
        print("=" * 65)
        print(f"\nDiagnostic report saved to: logs/{report_file.name}")

        # Save AI Candidate Fix (Isolated separately)
        fixed_code = extract_corrected_code(report_text)
        if fixed_code:
            candidate_path = DUT_DIR / f"{module_name}_candidate.v"
            patch_path = LOGS_DIR / f"{module_name}_patch.diff"

            with open(candidate_path, "w", encoding="utf-8") as f:
                f.write(fixed_code)

            diff = difflib.unified_diff(
                dut_code.splitlines(keepends=True),
                fixed_code.splitlines(keepends=True),
                fromfile=f"a/{dut_path.name}",
                tofile=f"b/{dut_path.name}"
            )
            diff_text = "".join(diff)
            with open(patch_path, "w", encoding="utf-8") as f:
                f.write(diff_text)

            print(f"\n[CANDIDATE FIX] Proposed RTL fix isolated at: {candidate_path.name}")
            print(f"[CANDIDATE FIX] Unified diff saved at: logs/{patch_path.name}")

            # Pre-validate candidate in sandbox before any replacement
            print(f"[CANDIDATE CHECK] Pre-validating candidate RTL in sandbox isolation...")
            cand_ok, cand_msg = test_candidate_in_isolation(candidate_path, tb_path, module_name, iverilog_bin, vvp_bin)
            if cand_ok:
                print(f"✅ [CANDIDATE VERIFIED] {cand_msg}")
            else:
                print(f"❌ [CANDIDATE REJECTED] {cand_msg}")

            if auto_heal and apply_candidate:
                if not cand_ok:
                    print("[SAFETY GUARD] Aborting auto-heal: Candidate failed isolated sandbox test. Validated RTL untouched.")
                    return False

                backup_path = dut_path.with_suffix(".v.bak")
                shutil.copyfile(dut_path, backup_path)
                print(f"[SELF-HEALING] Backup created at: {backup_path.name}")
                applied_successfully = False
                try:
                    shutil.copyfile(candidate_path, dut_path)
                    print(f"[SELF-HEALING] Applied verified candidate to {dut_path.name}. Running full verification...")
                    final_ok = run_pipeline(dut_path, no_ai=True)
                    if final_ok:
                        applied_successfully = True
                        print(f"🎉 [SELF-HEALING] Candidate successfully verified and deployed.")
                        return True
                    else:
                        print(f"⚠️ [SAFETY ROLLBACK] Verification failed after applying candidate! Restoring {dut_path.name} from backup...")
                        return False
                except (Exception, KeyboardInterrupt) as exc:
                    print(f"⚠️ [SAFETY ROLLBACK] Unexpected exception/timeout during verification ({exc})! Restoring {dut_path.name} from backup...")
                    return False
                finally:
                    if not applied_successfully and backup_path.exists():
                        shutil.copyfile(backup_path, dut_path)
                        print(f"[SAFETY ROLLBACK] Original {dut_path.name} safely restored from backup.")
                    if backup_path.exists():
                        backup_path.unlink()
            elif auto_heal:
                print("[NOTICE] Auto-heal candidate evaluated. Pass '--apply-candidate' to apply verified candidate to RTL.")
    except Exception as e:
        print(f"[!] AI Diagnostic generation failed: {e}")

    return False

def generate_dashboard(results: list):
    """Generate HTML and Markdown regression summary dashboards using project-relative paths."""
    md_file = LOGS_DIR / "regression_dashboard.md"
    html_file = LOGS_DIR / "regression_dashboard.html"

    total = len(results)
    passed = sum(1 for r in results if r["status"] == "PASSED")
    failed = total - passed
    pass_rate = (passed / total * 100) if total > 0 else 0

    # Markdown Dashboard (Strictly portable relative links)
    md_content = f"""# AutoVerify-VLSI: Regression Summary Dashboard

**Overall Status**: {'🟢 ALL PASSED' if failed == 0 else '🔴 FAILURES DETECTED'}  
**Modules Tested**: {total} | **Passed**: {passed} | **Failed**: {failed} | **Pass Rate**: {pass_rate:.1f}%

| Module | Status | Errors | VCD Waveform | Diagnostics |
| :--- | :---: | :---: | :--- | :--- |
"""
    for r in results:
        status_badge = "✅ PASSED" if r["status"] == "PASSED" else "❌ FAILED"
        vcd_link = f"[`{r['module']}.vcd`]({r['module']}.vcd)" if r['vcd'].exists() else "N/A"
        diag_link = f"[`Report`]({r['report'].name})" if r['report'].exists() else "None (Clean)"
        md_content += f"| **{r['module']}** | {status_badge} | {r['errors']} | {vcd_link} | {diag_link} |\n"

    with open(md_file, "w", encoding="utf-8") as f:
        f.write(md_content)

    # HTML Dashboard (Portable relative links)
    html_content = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>AutoVerify-VLSI Regression Dashboard</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 40px; }}
  .container {{ max-width: 900px; margin: 0 auto; background: #1e293b; border-radius: 12px; padding: 30px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }}
  h1 {{ margin-top: 0; color: #38bdf8; font-size: 28px; }}
  .stats {{ display: flex; gap: 20px; margin: 25px 0; }}
  .stat-card {{ background: #334155; padding: 15px 25px; border-radius: 8px; flex: 1; text-align: center; }}
  .stat-value {{ font-size: 28px; font-weight: bold; margin-bottom: 5px; }}
  .stat-label {{ color: #94a3b8; font-size: 14px; text-transform: uppercase; }}
  table {{ width: 100%; border-collapse: collapse; margin-top: 20px; }}
  th, td {{ padding: 12px 16px; text-align: left; border-bottom: 1px solid #475569; }}
  th {{ background: #0f172a; color: #cbd5e1; font-size: 14px; }}
  .badge-pass {{ background: #166534; color: #bbf7d0; padding: 4px 10px; border-radius: 9999px; font-size: 12px; font-weight: 600; display: inline-block; }}
  .badge-fail {{ background: #991b1b; color: #fecaca; padding: 4px 10px; border-radius: 9999px; font-size: 12px; font-weight: 600; display: inline-block; }}
  a {{ color: #38bdf8; text-decoration: none; }}
  a:hover {{ text-decoration: underline; }}
</style>
</head>
<body>
<div class="container">
  <h1>AutoVerify-VLSI: Regression Dashboard</h1>
  <div class="stats">
    <div class="stat-card"><div class="stat-value" style="color: #38bdf8;">{total}</div><div class="stat-label">Total Modules</div></div>
    <div class="stat-card"><div class="stat-value" style="color: #4ade80;">{passed}</div><div class="stat-label">Passed</div></div>
    <div class="stat-card"><div class="stat-value" style="color: #f87171;">{failed}</div><div class="stat-label">Failed</div></div>
    <div class="stat-card"><div class="stat-value" style="color: #fbbf24;">{pass_rate:.1f}%</div><div class="stat-label">Pass Rate</div></div>
  </div>
  <table>
    <thead><tr><th>Module</th><th>Status</th><th>Errors</th><th>Waveforms</th><th>Diagnostics</th></tr></thead>
    <tbody>
"""
    for r in results:
        badge = '<span class="badge-pass">PASSED</span>' if r["status"] == "PASSED" else '<span class="badge-fail">FAILED</span>'
        vcd_str = f'<a href="{r["vcd"].name}">{r["module"]}.vcd</a>' if r['vcd'].exists() else "N/A"
        diag_str = f'<a href="{r["report"].name}">Report</a>' if r['report'].exists() else "None (Clean)"
        html_content += f'<tr><td><strong>{r["module"]}</strong></td><td>{badge}</td><td>{r["errors"]}</td><td>{vcd_str}</td><td>{diag_str}</td></tr>\n'

    html_content += """    </tbody>
  </table>
</div>
</body>
</html>"""

    with open(html_file, "w", encoding="utf-8") as f:
        f.write(html_content)

    print(f"\n[DASHBOARD] Generated Regression Dashboard:")
    print(f"  Markdown: logs/regression_dashboard.md")
    print(f"  HTML:     logs/regression_dashboard.html")

def run_regression(no_ai: bool, regen_tb: bool, model_name: str, auto_heal: bool, apply_candidate: bool) -> bool:
    """Run full verification regression suite across all DUTs in dut/."""
    dut_files = sorted([f for f in DUT_DIR.glob("*.v") if not f.name.endswith(("_candidate.v", "_bak.v"))])
    if not dut_files:
        print(f"[ERROR] No Verilog DUT files found in {DUT_DIR}")
        return False

    print("\n" + "=" * 65)
    print(f" STARTING REGRESSION SUITE ({len(dut_files)} Modules Found) ")
    print("=" * 65)

    results = []
    all_passed = True
    for dut in dut_files:
        module_name = dut.stem
        passed = run_pipeline(
            dut,
            no_ai=no_ai,
            regen_tb=regen_tb,
            model_name=model_name,
            auto_heal=auto_heal,
            apply_candidate=apply_candidate
        )
        if not passed:
            all_passed = False

        sim_log = LOGS_DIR / f"{module_name}_sim.log"
        error_count = 0
        if sim_log.exists():
            with open(sim_log, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                matches = re.findall(r"Total Errors\s*=\s*(\d+)", content)
                if matches:
                    error_count = int(matches[-1])
                elif not passed:
                    error_count = len(re.findall(r"\[FAIL\]", content)) or 1

        results.append({
            "module": module_name,
            "status": "PASSED" if passed else "FAILED",
            "errors": error_count,
            "vcd": LOGS_DIR / f"{module_name}.vcd",
            "report": LOGS_DIR / f"{module_name}_report.md"
        })

    generate_dashboard(results)
    return all_passed

def main():
    parser = argparse.ArgumentParser(description="AutoVerify-VLSI: Autonomous RTL Verification & Self-Healing Agent")
    parser.add_argument("--dut", type=str, default=None, help="Path to DUT Verilog file (e.g. dut/alu.v)")
    parser.add_argument("--regression", action="store_true", help="Run full regression on all modules in dut/")
    parser.add_argument("--no-ai", action="store_true", help="Run deterministic offline verification without Gemini API calls")
    parser.add_argument("--regen-tb", action="store_true", help="Force AI to regenerate testbench even if one exists")
    parser.add_argument("--auto-heal", action="store_true", help="Diagnose failures and generate candidate fix file")
    parser.add_argument("--apply-candidate", action="store_true", help="Apply candidate fix directly to RTL after review")
    parser.add_argument("--model", type=str, default="gemini-2.5-flash", help="Gemini model name")
    args = parser.parse_args()

    # Configure Gemini API only if AI mode is needed
    if not args.no_ai:
        api_key = get_api_key(required=False)
        if api_key:
            try:
                import google.generativeai as genai
                genai.configure(api_key=api_key)
            except ImportError:
                print("[WARNING] 'google-generativeai' package not installed. Running in '--no-ai' mode.")
                args.no_ai = True
        else:
            args.no_ai = True

    if args.regression:
        success = run_regression(
            no_ai=args.no_ai,
            regen_tb=args.regen_tb,
            model_name=args.model,
            auto_heal=args.auto_heal,
            apply_candidate=args.apply_candidate
        )
        sys.exit(0 if success else 1)

    dut_target = args.dut or "dut/alu.v"
    dut_path = Path(dut_target)
    if not dut_path.is_absolute():
        dut_path = ROOT_DIR / dut_path

    if not dut_path.exists():
        print(f"[ERROR] DUT file not found: {dut_path}")
        sys.exit(1)

    success = run_pipeline(
        dut_path,
        no_ai=args.no_ai,
        regen_tb=args.regen_tb,
        model_name=args.model,
        auto_heal=args.auto_heal,
        apply_candidate=args.apply_candidate
    )
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
