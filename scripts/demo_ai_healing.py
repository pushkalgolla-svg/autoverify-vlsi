#!/usr/bin/env python3
"""
AutoVerify-VLSI: AI-Assisted Self-Healing Demonstration Script

Demonstrates the automated diagnostic and candidate repair workflow:
  1. Executes verification on an isolated, deliberately faulty RTL copy (examples/faulty_rtl/alu_faulty.v).
  2. Identifies the functional failure (inverted borrow flag on subtraction underflow).
  3. Diagnoses root cause via Gemini API (when GEMINI_API_KEY is available) or deterministic offline demonstration.
  4. Generates an isolated candidate fix and unified patch diff.
  5. Pre-validates the candidate in a sandboxed simulation before any deployment.
  6. Enforces strict safety guardrails: original validated RTL ('dut/alu.v') remains 100% untouched.
"""

import os
import re
import sys
import shutil
import difflib
import argparse
import subprocess
from pathlib import Path

# Force UTF-8 console output on Windows
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT_DIR = Path(__file__).resolve().parent.parent
DUT_ORIGINAL = ROOT_DIR / "dut" / "alu.v"
TB_PATH = ROOT_DIR / "testbenches" / "tb_alu.v"
EXAMPLES_DIR = ROOT_DIR / "examples" / "faulty_rtl"
LOGS_DIR = ROOT_DIR / "logs"

FAULTY_RTL = EXAMPLES_DIR / "alu_faulty.v"
REF_FIXED_RTL = EXAMPLES_DIR / "alu_reference_fixed.v"
CANDIDATE_RTL = EXAMPLES_DIR / "alu_candidate.v"
DIFF_PATCH = EXAMPLES_DIR / "alu_healing_patch.diff"
HEALING_REPORT = EXAMPLES_DIR / "alu_healing_report.md"

ENV_FILE = ROOT_DIR / ".env"

def load_env():
    """Load environment variables from .env using standard library parser."""
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

def find_tool(tool_name: str) -> str:
    """Find EDA binary on PATH or standard local paths."""
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
    raise FileNotFoundError(f"Could not locate required EDA tool '{tool_name}'.")

def clean_code_block(text: str) -> str:
    """Extract code from markdown code fences."""
    pattern = r"```(?:verilog|systemverilog)?\s*(.*?)\s*```"
    match = re.search(pattern, text, re.DOTALL | re.IGNORECASE)
    return match.group(1).strip() if match else text.strip()

def main():
    parser = argparse.ArgumentParser(description="AutoVerify-VLSI: AI-Assisted Self-Healing Demonstration")
    parser.add_argument("--offline", action="store_true", help="Run deterministic offline demonstration without external API calls")
    parser.add_argument("--model", type=str, default="gemini-2.5-flash", help="Gemini model name")
    args = parser.parse_args()

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    EXAMPLES_DIR.mkdir(parents=True, exist_ok=True)

    iverilog_bin = find_tool("iverilog")
    vvp_bin = find_tool("vvp")

    print("\n" + "=" * 70)
    print(" AutoVerify-VLSI: AI-Assisted Self-Healing Demonstration ")
    print("=" * 70)

    # Step 0: Record original validated RTL fingerprint
    with open(DUT_ORIGINAL, "rb") as f:
        orig_bytes = f.read()

    print(f"\n[Step 1/5] Setting up isolated faulty copy for demonstration...")
    print(f"  Target Faulty Copy: examples/faulty_rtl/{FAULTY_RTL.name}")
    print(f"  Protected Production RTL: dut/{DUT_ORIGINAL.name}")

    if not FAULTY_RTL.exists():
        print(f"[ERROR] Faulty demonstration RTL not found at: {FAULTY_RTL}")
        sys.exit(1)

    with open(FAULTY_RTL, "r", encoding="utf-8") as f:
        faulty_code = f.read()

    # Step 1: Run verification on faulty RTL in isolated sandbox
    print(f"\n[Step 2/5] Compiling and simulating faulty RTL against testbench...")
    sim_bin = LOGS_DIR / "demo_faulty_sim.vvp"
    if sim_bin.exists():
        sim_bin.unlink()

    comp_res = subprocess.run([iverilog_bin, "-g2012", "-o", str(sim_bin), str(FAULTY_RTL), str(TB_PATH)],
                              capture_output=True, text=True)
    if comp_res.returncode != 0:
        print(f"[ERROR] Faulty RTL failed compilation:\n{comp_res.stderr}")
        sys.exit(1)

    sim_res = subprocess.run([vvp_bin, str(sim_bin)], capture_output=True, text=True)
    sim_out = sim_res.stdout + sim_res.stderr
    if sim_bin.exists():
        sim_bin.unlink()

    # Confirm that the injected defect was caught
    has_failed = "[FAIL]" in sim_out or "SIMULATION FAILED" in sim_out
    if not has_failed:
        print("[ERROR] Expected defect was not caught by testbench! Check tb_alu.v.")
        sys.exit(1)

    fail_lines = [l for l in sim_out.splitlines() if "[FAIL]" in l or "SIMULATION FAILED" in l]
    print(f"✅ Injected defect successfully caught! Highlighted failures:")
    for fl in fail_lines[:4]:
        print(f"   {fl}")

    # Step 2: AI Diagnostic or Deterministic Offline Diagnostic
    load_env()
    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    use_online_ai = (not args.offline) and bool(api_key)

    fixed_code = None
    report_text = ""

    if use_online_ai:
        print(f"\n[Step 3/5] Engaging Gemini ({args.model}) for automated diagnostic...")
        try:
            import google.generativeai as genai
            genai.configure(api_key=api_key)
            prompt = f"""You are a Principal ASIC/FPGA Verification Engineer.
A Verilog simulation of an ALU failed. Analyze the RTL and simulation log to diagnose the defect.

=== RTL Source (alu.v) ===
{faulty_code}

=== Simulation Failure Output ===
{sim_out}

Provide a structured report:
1. Executive Summary: What failed in the simulation.
2. Root Cause Classification: RTL Design Error vs Testbench Discrepancy.
3. Technical Explanation: Pinpoint exact line and logic causing borrow underflow failure.
4. Unified Diff: Show the fix.
5. Corrected RTL Code: Enclosed in ```verilog ... ```.
"""
            model = genai.GenerativeModel(args.model)
            response = model.generate_content(prompt)
            report_text = response.text
            fixed_code = clean_code_block(report_text)
            print("✅ Online Gemini diagnostic analysis received.")
        except Exception as e:
            print(f"[WARNING] Online AI call failed ({e}). Falling back to deterministic offline demonstration.")
            use_online_ai = False

    if not use_online_ai:
        print(f"\n[Step 3/5] Running Deterministic Offline Self-Healing Diagnostic...")
        print("  [INFO] GEMINI_API_KEY not present or --offline requested.")
        print("  [INFO] Demonstration uses verified golden diagnostic and reference repair model.")

        with open(REF_FIXED_RTL, "r", encoding="utf-8") as f:
            fixed_code = f.read()

        report_text = f"""# AutoVerify-VLSI: AI-Assisted Self-Healing Diagnostic Report

**Mode:** Deterministic Offline Demonstration Mode  
**Target Module:** `examples/faulty_rtl/alu_faulty.v`  
**Defect Classification:** 🔴 **RTL Design Defect** (Logic Inversion)  

---

## 1. Executive Summary
The simulation of `alu_faulty.v` failed multiple directed and randomized test assertions under subtraction operations (`op = 2'b01`).
Specifically, when an unsigned underflow occurred (`a < b`, e.g., `0 - 1`), the ALU outputted `carry = 0` instead of asserting the borrow flag (`carry = 1`). Conversely, when `a > b`, `carry` was incorrectly asserted as `1`.

---

## 2. Root Cause Analysis
- **Location:** Line 34 of `examples/faulty_rtl/alu_faulty.v`
- **Faulty Expression:** `carry = (a > b);`
- **Root Cause:** The borrow condition comparison was inverted. In standard unsigned binary subtraction, a borrow (underflow) occurs when the minuend `a` is strictly less than the subtrahend `b` (`a < b`).

---

## 3. Corrective Patch
```diff
--- a/examples/faulty_rtl/alu_faulty.v
+++ b/examples/faulty_rtl/alu_candidate.v
@@ -31,3 +31,3 @@
             2'b01: begin
                 result = a - b;
-                carry  = (a > b); // INJECTED DEFECT: Inverted comparison condition!
+                carry  = (a < b); // Explicit borrow indicator: 1 if underflow (a < b)
             end
```

---

## 4. Corrected RTL Code
```verilog
{fixed_code}
```
"""

    # Save Diagnostic Report
    with open(HEALING_REPORT, "w", encoding="utf-8") as f:
        f.write(report_text)
    print(f"  Saved diagnostic report: examples/faulty_rtl/{HEALING_REPORT.name}")

    # Save Candidate RTL (Isolated in examples/)
    with open(CANDIDATE_RTL, "w", encoding="utf-8") as f:
        f.write(fixed_code)
    print(f"  Isolated candidate fix: examples/faulty_rtl/{CANDIDATE_RTL.name}")

    # Generate Unified Diff
    diff = list(difflib.unified_diff(
        faulty_code.splitlines(keepends=True),
        fixed_code.splitlines(keepends=True),
        fromfile="a/alu_faulty.v",
        tofile="b/alu_candidate.v"
    ))
    diff_text = "".join(diff)
    with open(DIFF_PATCH, "w", encoding="utf-8") as f:
        f.write(diff_text)
    print(f"  Generated patch diff: examples/faulty_rtl/{DIFF_PATCH.name}")
    print("\n--- Candidate Unified Diff ---")
    print(diff_text.strip())
    print("------------------------------\n")

    # Step 3: Sandboxed Candidate Pre-Validation
    print(f"[Step 4/5] Pre-validating candidate fix in sandboxed simulation...")
    cand_bin = LOGS_DIR / "demo_candidate_sim.vvp"
    if cand_bin.exists():
        cand_bin.unlink()

    cand_comp = subprocess.run([iverilog_bin, "-g2012", "-o", str(cand_bin), str(CANDIDATE_RTL), str(TB_PATH)],
                               capture_output=True, text=True)
    if cand_comp.returncode != 0:
        print(f"❌ Candidate compilation failed:\n{cand_comp.stderr}")
        sys.exit(1)

    cand_sim = subprocess.run([vvp_bin, str(cand_bin)], capture_output=True, text=True)
    cand_out = cand_sim.stdout + cand_sim.stderr
    if cand_bin.exists():
        cand_bin.unlink()

    cand_passed = "ALL TESTS PASSED" in cand_out and "[FAIL]" not in cand_out
    if cand_passed:
        print("🎉 Candidate RTL passed 100% of functional verification and coverage checks in sandbox!")
    else:
        print(f"❌ Candidate failed verification checks:\n{cand_out}")
        sys.exit(1)

    # Step 4: Verify Safety Guardrails
    print(f"\n[Step 5/5] Verifying Production Safety Guardrails...")
    with open(DUT_ORIGINAL, "rb") as f:
        post_bytes = f.read()

    if orig_bytes == post_bytes:
        print(f"🔒 [PASS] Production RTL 'dut/{DUT_ORIGINAL.name}' is verified 100% UNTOUCHED.")
    else:
        print(f"⚠️ [CRITICAL] Production RTL was modified! Restoring...")
        with open(DUT_ORIGINAL, "wb") as f:
            f.write(orig_bytes)
        sys.exit(1)

    print(f"🔒 [PASS] Approval Gate Enforced: Candidate remains isolated in 'examples/faulty_rtl/'.")
    print(f"         No automated promotion occurs without explicit engineering authorization.")

    print("\n" + "=" * 70)
    print(" ✅ AI-Assisted Self-Healing Demonstration Successfully Completed ")
    print("=" * 70 + "\n")

if __name__ == "__main__":
    main()
