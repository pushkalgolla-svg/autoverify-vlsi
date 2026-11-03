## ASIC/FPGA Verification Report

**Module Under Test:** `uart_tx.v`

**1. Executive Summary**

The Verilog simulation of the `uart_tx` module failed with 133 errors. Initial analysis of the simulation log reveals two primary categories of failures:

1.  **Initial Transmission Failures (First `send_and_verify` call):** The first data transmission (0x55, no parity) reported that `tx_busy` did not assert, the `tx` line remained HIGH (did not go LOW for the start bit), and subsequent data bits were also incorrectly HIGH. These failures occurred prematurely at the very start of the transmission.
2.  **Persistent `tx_done` Failure (All `send_and_verify` calls):** Across all directed and random tests, the `tx_done` output signal was consistently reported as "did not pulse after transmission". Other checks like parity bit value and `tx_busy` deassertion often passed in subsequent tests, but `tx_done` always failed.

The root causes were identified as a **testbench timing error** for initial signal checks and a **bug in the RTL's stop bit duration logic**.

**2. Root Cause Classification**

*   **RTL Design Bug:** The primary functional bug causing the `tx_done` failure and premature end of transmission resides in `uart_tx.v`.
*   **Testbench Bug:** The initial failures observed in the very first transmission (e.g., `tx_busy` not asserting, `tx` line remaining high) are due to incorrect timing in the `tb_uart_tx.v` when sampling DUT outputs immediately after driving inputs.

**3. Detailed Technical Explanation**

**3.1. Testbench Timing Issue (Initial Failures)**

*   **Problem:** In the `send_and_verify` task, after driving `tx_start`, `din`, and `parity_mode`, the testbench waits for one `posedge clk` for the DUT to sample inputs:
    ```verilog
    // Drive inputs
    tx_start = 1'b1;
    // ... other inputs ...
    @(posedge clk) begin end // DUT samples inputs here
    tx_start = 1'b0;

    // Checks tx_busy and tx immediately after tx_start deassertion,
    // but before DUT outputs have updated.
    if (dut.tx_busy != 1'b1) begin // This check is premature
    ```
*   **Mechanics:** In `uart_tx.v`, `tx_busy` and `tx` are `reg` outputs from an `always @(posedge clk or negedge rst_n)` block, and are updated using non-blocking assignments (`<=`). When the DUT samples `tx_start` on a `posedge clk` (e.g., at `T1`), the new values for `tx_busy` and `tx` are *scheduled* to update at the very end of the `T1` time step, becoming visible only at the start of the *next* clock cycle (i.e., `T1 + CLOCK_PERIOD`). The testbench, however, checks these outputs immediately after the `@(posedge clk)` statement that *triggered* the DUT's internal logic, leading to sampling stale (old) values. This results in the `tx_busy` and `tx` checks failing for the first transmission. The subsequent `data bit mismatch` failures are a direct consequence of the `tx` line not going low for the start bit.
*   **Log Evidence:**
    *   `[FAIL] 75000: tx_busy did not go HIGH after tx_start...`
    *   `[FAIL] 75000: Initial tx line is not LOW (start bit)...`
    *   `[FAIL] ... Data bit X mismatch...` (all these occur at the beginning of the first `send_and_verify` call).

**3.2. RTL Bug: Premature Stop Bit Termination (`tx_done` Failure)**

*   **Problem:** The `uart_tx` module terminates the stop bit prematurely, causing a framing error and impacting the `tx_done` signal's timing.
*   **Mechanics:** In `uart_tx.v`, inside the `STATE_STOP` block, the counter condition to transition back to `STATE_IDLE` is incorrect:
    ```verilog
    STATE_STOP: begin
        tx <= 1'b1; // Stop bit is HIGH
        // INJECTED BUG: Ends stop bit prematurely at clk_count == 2
        // instead of waiting for full CLKS_PER_BIT - 1!
        if (clk_count < 2) begin // <-- BUG: Should be CLKS_PER_BIT - 1
            clk_count <= clk_count + 1'b1;
        end else begin
            clk_count <= 16'd0;
            tx_done   <= 1'b1; // tx_done pulses here
            state     <= STATE_IDLE;
        end
    end
    ```
    This logic means the stop bit lasts for only 3 clock cycles (`clk_count` values 0, 1, 2) instead of `CLKS_PER_BIT` (10 cycles in this simulation). The `tx_done` signal is pulsed at the end of this shortened stop bit.
    The testbench, however, is designed to wait for the *full* `CLKS_PER_BIT` duration for the stop bit and expects `tx_done` to pulse at that correct, later time. Because the DUT pulses `tx_done` too early, and the testbench's observation window for `tx_done` during the *expected* full stop bit duration (which starts later than the actual pulse) misses this premature pulse. Even if caught, the timing would be incorrect.
*   **Log Evidence:**
    *   `[FAIL] ... tx_done did not pulse after transmission ...` (This error occurs for *every single* `send_and_verify` call, indicating a fundamental timing or functional issue with `tx_done`).

**4. Corrective Code Diff**

```diff
--- a/uart_tx.v
+++ b/uart_tx.v
@@ -99,7 +99,7 @@
                 STATE_STOP: begin
                     tx <= 1'b1; // Stop bit is HIGH
                     // INJECTED BUG: Ends stop bit prematurely at clk_count == 2
-                    // instead of waiting for full CLKS_PER_BIT - 1!
-                    if (clk_count < 2) begin
+                    // Corrected to wait for full CLKS_PER_BIT - 1
+                    if (clk_count < CLKS_PER_BIT - 1) begin
                         clk_count <= clk_count + 1'b1;
                     end else begin
                         clk_count <= 16'd0;
--- a/tb_uart_tx.v
+++ b/tb_uart_tx.v
@@ -82,6 +82,7 @@
             // Wait for one clock cycle for inputs to register (tx_start is sampled on posedge clk)
             @(posedge clk) begin end 
             tx_start    = 1'b0;
+            @(posedge clk) begin end // Wait one more cycle for DUT outputs to update

             // Check tx_busy assertion
             if (dut.tx_busy != 1'b1) begin

```

**5. Corrected RTL Code**

```verilog
`timescale 1ns / 1ps

/**
 * UART Transmitter with Configurable Baud Rate and Parity
 *
 * Parameters:
 *   CLKS_PER_BIT : Clock cycles per baud period (default 10 for fast simulation)
 *
 * States:
 *   IDLE, START, DATA, PARITY, STOP
 */

module uart_tx #(
    parameter CLKS_PER_BIT = 10
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] din,
    input  wire [1:0] parity_mode, // 2'b00: None, 2'b01: Odd, 2'b10: Even
    output reg        tx,
    output reg        tx_busy,
    output reg        tx_done
);

    localparam [2:0]
        STATE_IDLE   = 3'b000,
        STATE_START  = 3'b001,
        STATE_DATA   = 3'b010,
        STATE_PARITY = 3'b011,
        STATE_STOP   = 3'b100;

    reg [2:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  tx_data;
    reg        parity_bit;

    // Parity calculation
    wire parity_odd  = ~(^tx_data);
    wire parity_even = ^tx_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= STATE_IDLE;
            clk_count  <= 16'd0;
            bit_index  <= 3'd0;
            tx_data    <= 8'd0;
            parity_bit <= 1'b0;
            tx         <= 1'b1; // Idle line is HIGH
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
        end else begin
            tx_done <= 1'b0; // Default pulse

            case (state)
                STATE_IDLE: begin
                    tx        <= 1'b1;
                    tx_busy   <= 1'b0;
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;

                    if (tx_start) begin
                        tx_data    <= din;
                        tx_busy    <= 1'b1;
                        tx         <= 1'b0; // Start bit is LOW
                        state      <= STATE_START;
                        
                        if (parity_mode == 2'b01)
                            parity_bit <= ~(^din);
                        else if (parity_mode == 2'b10)
                            parity_bit <= ^din;
                        else
                            parity_bit <= 1'b0;
                    end
                end

                STATE_START: begin
                    tx <= 1'b0;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        state     <= STATE_DATA;
                    end
                end

                STATE_DATA: begin
                    tx <= tx_data[bit_index];
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        if (bit_index < 3'd7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= 3'd0;
                            if (parity_mode != 2'b00)
                                state <= STATE_PARITY;
                            else
                                state <= STATE_STOP;
                        end
                    end
                end

                STATE_PARITY: begin
                    tx <= parity_bit;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        state     <= STATE_STOP;
                    end
                end

                STATE_STOP: begin
                    tx <= 1'b1; // Stop bit is HIGH
                    // Corrected to wait for full CLKS_PER_BIT - 1
                    if (clk_count < CLKS_PER_BIT - 1) begin 
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        tx_done   <= 1'b1;
                        state     <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
```