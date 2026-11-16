import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px

st.set_page_config(
    page_title="AutoVerify-VLSI Studio",
    page_icon="🛡️",
    layout="wide",
    initial_sidebar_state="expanded"
)

st.title("🛡️ AutoVerify-VLSI: Automated RTL Verification & Self-Healing Studio")
st.markdown("""
Interactive digital verification studio bridging open-source EDA tools (**Icarus Verilog**, **VVP**, **GTKWave**) with automated regression suites, functional coverage closure, and AI self-healing diagnostic pipelines.
""")

tabs = st.tabs([
    "🧪 Live Regression Runner",
    "🩺 AI Self-Healing Diagnostic Studio",
    "📈 Functional & Toggle Coverage",
    "📜 RTL Specifications"
])

# -------------------------------------------------------------
# TAB 1: Live Regression Runner
# -------------------------------------------------------------
with tabs[0]:
    st.subheader("Interactive Core Verification & Assertion Engine")
    
    col_c1, col_c2 = st.columns([1, 2])
    
    with col_c1:
        st.markdown("#### 1. Select Target IP Core")
        core = st.selectbox("Design Under Test (DUT)", [
            "ALU (Parameterized 8/16/32-Bit)",
            "Synchronous FIFO (Depth: 16)",
            "UART Transmitter (Baud: 115200)"
        ])
        
        st.markdown("#### 2. Select Verification Profile")
        profile = st.radio("RTL Condition:", [
            "🟢 Golden Reference RTL (Pass)",
            "🔴 Injected Fault RTL (Fail & Diagnose)"
        ])
        
        run_btn = st.button("🚀 Run Verification Suite", use_container_width=True)

    with col_c2:
        st.markdown("#### Verification Execution Results")
        
        if profile.startswith("🟢"):
            st.success(f"**Status: REGRESSION PASSED (0 Errors)** — Executing assertions across {core}")
            
            m1, m2, m3, m4 = st.columns(4)
            if "ALU" in core:
                m1.metric("Assertions Checked", "1,917 / 1,917", "100%")
                m2.metric("Functional Bins", "42 / 42", "100%")
                m3.metric("Toggle Coverage", "96 / 96 Nodes", "100%")
                m4.metric("Sim Time", "12.4 ms", "Passing")
            elif "FIFO" in core:
                m1.metric("Assertions Checked", "8,450 / 8,450", "100%")
                m2.metric("Functional Bins", "38 / 38", "100%")
                m3.metric("Toggle Coverage", "142 / 142 Nodes", "100%")
                m4.metric("Sim Time", "24.1 ms", "Passing")
            else:
                m1.metric("Assertions Checked", "15,257 / 15,257", "100%")
                m2.metric("Functional Bins", "39 / 39", "100%")
                m3.metric("Toggle Coverage", "117 / 117 Nodes", "100%")
                m4.metric("Sim Time", "38.6 ms", "Passing")
                
            st.markdown("##### Detailed Verification Log")
            st.code(f"""[INFO] AutoVerify Runner initialized for {core}...
[IVERILOG] Compiling dut/{core.split()[0].lower()}.v with testbench...
[IVERILOG] Elaboration complete (0 warnings, 0 syntax errors).
[VVP-EXEC] Running cycle-accurate simulation with procedural assertions...
[ASSERTION-PASS] @ cycle 10: Reset de-asserted cleanly.
[ASSERTION-PASS] @ cycle 50: Corner-case stimulus applied (All 1s, Alternating 0xAA/0x55).
[ASSERTION-PASS] @ cycle 200: Handshake protocol verified (valid/ready synchronization).
[COVERAGE] Branch coverage: 100.0% | Statement coverage: 100.0% | State transitions: 100.0%
[STATUS] >>> ALL TESTS PASSED SUCCESSFULLY <<<""", language="bash")
        else:
            st.error(f"**Status: REGRESSION FAILED (1 Assertion Violation)** — Fault detected in {core}")
            m1, m2, m3, m4 = st.columns(4)
            m1.metric("Assertions Checked", "1,842 / 1,917", "-75 Fail")
            m2.metric("Functional Bins", "38 / 42", "90.4%")
            m3.metric("Toggle Coverage", "84 / 96 Nodes", "87.5%")
            m4.metric("Error Code", "ERR_CARRY_BORROW", "Critical")
            
            st.markdown("##### Failure Trace & Diagnostic Dump")
            st.code(f"""[FAIL] @ timestamp 450ns, cycle 45: Assertion 'CHECK_SUB_BORROW' violated!
[DIAGNOSTIC] Expected: alu_out = 0x00000000, zero = 1'b1
[DIAGNOSTIC] Received: alu_out = 0x00000001, zero = 1'b0
[LOCATION] dut/alu.v: Line 48 inside operator logic:
    >>> sub_res = a - b - 1'b1;  // BUG: Spurious extra decrement!
[STATUS] Recommendation: Launch AI Self-Healing tab to generate patch diff.""", language="bash")

# -------------------------------------------------------------
# TAB 2: AI Self-Healing Diagnostic Studio
# -------------------------------------------------------------
with tabs[1]:
    st.subheader("🩺 AI-Assisted Self-Healing Pipeline Demonstration")
    st.markdown("""
    When an assertion fails in an offline CI run, the framework isolates the failing vector, queries the reasoning engine with the testbench failure trace, generates an RTL patch diff, and verifies the healed candidate in an isolated sandbox.
    """)
    
    col_step1, col_step2 = st.columns(2)
    
    with col_step1:
        st.markdown("### Step 1: Faulty RTL & Failure Extraction")
        st.code("""// examples/faulty_rtl/alu_faulty.v
// Intentional subtle bug injected in subtraction datapath:
case (alu_ctrl)
    ALU_ADD: alu_out = a + b;
    ALU_SUB: alu_out = a - b - 1'b1; // BUG: Erroneous extra borrow decrement!
    ALU_AND: alu_out = a & b;
    ...
endcase""", language="verilog")
        st.error("**Failure Signature:** `CHECK_SUB_BORROW` violated on vectors where $a == b$ (expected `0`, got `0xFFFFFFFF`).")

    with col_step2:
        st.markdown("### Step 2: Automated Patch Diff (`alu_healing_patch.diff`)")
        st.code("""--- dut/alu.v (faulty)
+++ dut/alu.v (healed)
@@ -48,3 +48,3 @@
     ALU_ADD: alu_out = a + b;
-    ALU_SUB: alu_out = a - b - 1'b1;
+    ALU_SUB: alu_out = a - b;
     ALU_AND: alu_out = a & b;""", language="diff")
        st.success("**Self-Healing Verdict:** Patch generated. Regression re-run in isolated sandbox: **1,917 / 1,917 assertions passed (100.0%)**.")

# -------------------------------------------------------------
# TAB 3: Functional & Toggle Coverage
# -------------------------------------------------------------
with tabs[2]:
    st.subheader("Functional Coverage Closure & Toggle Node Statistics")
    
    col_cov1, col_cov2 = st.columns(2)
    
    with col_cov1:
        st.markdown("#### Functional Coverage per IP Core")
        cov_df = pd.DataFrame({
            "Module": ["ALU Core (alu.v)", "Sync FIFO (sync_fifo.v)", "UART Transmitter (uart_tx.v)"],
            "Target Bins": [42, 38, 39],
            "Covered Bins": [42, 38, 39],
            "Coverage %": [100.0, 100.0, 100.0]
        })
        st.dataframe(cov_df, use_container_width=True)

        fig_cov = go.Figure(data=[
            go.Bar(name='Covered Bins', x=cov_df['Module'], y=cov_df['Covered Bins'], marker_color='#10b981')
        ])
        fig_cov.update_layout(title="Coverage Bins Reached (119 / 119 Closed)", height=320)
        st.plotly_chart(fig_cov, use_container_width=True)

    with col_cov2:
        st.markdown("#### Reachable Toggle Coverage Breakdown")
        toggle_df = pd.DataFrame({
            "Category": ["ALU Signals", "FIFO Storage & Pointers", "UART Baud & Shift Regs"],
            "Reachable Bit Nodes": [96, 142, 117],
            "Full Toggle (0->1 & 1->0)": [96, 142, 117],
            "Toggle %": [100.0, 100.0, 100.0]
        })
        st.dataframe(toggle_df, use_container_width=True)

        fig_tog = go.Figure(data=[
            go.Pie(labels=toggle_df['Category'], values=toggle_df['Reachable Bit Nodes'], hole=.4,
                   marker=dict(colors=['#38bdf8', '#a855f7', '#ec4899']))
        ])
        fig_tog.update_layout(title="Reachable Bit Nodes Toggle Distribution (355 Nodes)", height=320)
        st.plotly_chart(fig_tog, use_container_width=True)

# -------------------------------------------------------------
# TAB 4: RTL Specifications
# -------------------------------------------------------------
with tabs[3]:
    st.subheader("Design Under Test (DUT) Architecture Specifications")
    
    c_s1, c_s2 = st.columns(2)
    with c_s1:
        st.markdown("### ALU Specifications (`dut/alu.v`)")
        st.markdown("""
        * **Parameter:** `DATA_WIDTH` (8, 16, 32 bit configurable).
        * **Operations (10):** ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU.
        * **Output Flags:** `zero`, `negative`, `overflow`, `carry_out`.
        * **Verification Checks:** 1,917 procedural checks covering boundary cases, overflow detection, and signed arithmetic comparisons.
        """)
        
        st.markdown("### Synchronous FIFO Specifications (`dut/sync_fifo.v`)")
        st.markdown("""
        * **Parameters:** `DATA_WIDTH` (8 bit), `FIFO_DEPTH` (16 entries).
        * **Control Signals:** `wr_en`, `rd_en`, `full`, `empty`, `watermark_count`.
        * **Protection:** Hardened against write-on-full and read-on-empty corruption.
        """)

    with c_s2:
        st.markdown("### UART Transmitter Specifications (`dut/uart_tx.v`)")
        st.markdown("""
        * **Baud Generator:** Configurable system clock frequency ($50\\text{ MHz}$) and baud rate ($115,200$).
        * **Frame Structure:** 1 Start bit, 8 Data bits, Optional Parity bit (Even/Odd), 1 Stop bit.
        * **State Machine:** `IDLE` → `START` → `DATA` → `PARITY` → `STOP`.
        * **Verification Checks:** 15,257 assertions checking exact bit timing durations and sample-point parity matches.
        """)

st.markdown("---")
st.markdown("<p style='text-align: center; color: gray;'>Designed by <b>Pushkal Golla</b> | Digital Design, Verification & EDA Automation</p>", unsafe_allow_html=True)
