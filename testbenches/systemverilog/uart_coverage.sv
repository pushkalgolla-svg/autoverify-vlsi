// =============================================================================
// AutoVerify-VLSI: SystemVerilog IEEE 1800 Reference Functional Coverage Model
// Module: uart_coverage.sv
// Target: Commercial EDA Simulators (Synopsys VCS, Cadence Xcelium, Siemens Questa)
// Note  : For open-source CI (Icarus Verilog), portable procedural coverage in
//         testbenches/tb_uart_tx.v is executed.
// =============================================================================

`timescale 1ns / 1ps

package uart_cov_pkg;

    class uart_coverage_model;

        // Transaction variables sampled by covergroup
        logic [7:0] din;
        logic [1:0] parity_mode;
        logic       tx_start;
        logic       tx_busy;
        logic       tx_done;
        logic       tx_line;

        event sample_event;

        // IEEE 1800 Covergroup Specification
        covergroup cg_uart @(posedge sample_event);
            option.per_instance = 1;
            option.name = "cg_uart_tx";

            // Parity Mode Coverage (All 4 settings)
            cp_parity_mode: coverpoint parity_mode {
                bins mode_none     = {2'b00};
                bins mode_odd      = {2'b01};
                bins mode_even     = {2'b10};
                bins mode_reserved = {2'b11}; // Treated safely as No Parity
            }

            // Input Data Pattern Coverage
            cp_din: coverpoint din {
                bins val_all_zeros = {8'h00};
                bins val_all_ones  = {8'hFF};
                bins val_alt_55    = {8'h55};
                bins val_alt_AA    = {8'hAA};
                bins walking_ones[] = {
                    8'h01, 8'h02, 8'h04, 8'h08,
                    8'h10, 8'h20, 8'h40, 8'h80
                };
                bins general_data  = default;
            }

            // Handshake Signal Coverage
            cp_tx_busy: coverpoint tx_busy {
                bins idle   = {1'b0};
                bins active = {1'b1};
                bins trans_active = (0 => 1 => 0);
            }

            cp_tx_done: coverpoint tx_done {
                bins idle  = {1'b0};
                bins pulse = {1'b1};
                bins exact_one_pulse = (0 => 1 => 0);
            }

            // Request During Transmission (Rejection verification)
            cross_busy_start: cross cp_tx_busy, tx_start {
                bins req_while_idle = binsof(cp_tx_busy.idle) && binsof(tx_start) intersect {1'b1};
                bins req_while_busy = binsof(cp_tx_busy.active) && binsof(tx_start) intersect {1'b1};
            }

            // Cross Coverage: Parity Mode x Key Data Patterns
            cross_mode_data: cross cp_parity_mode, cp_din {
                bins none_patterns = binsof(cp_parity_mode.mode_none) && (binsof(cp_din.val_all_zeros) || binsof(cp_din.val_all_ones));
                bins odd_patterns  = binsof(cp_parity_mode.mode_odd)  && (binsof(cp_din.val_alt_55)    || binsof(cp_din.val_alt_AA));
                bins even_patterns = binsof(cp_parity_mode.mode_even) && (binsof(cp_din.val_alt_55)    || binsof(cp_din.val_alt_AA));
            }
        endgroup

        function new();
            cg_uart = new();
        endfunction

        function void sample(
            input logic [7:0] s_din,
            input logic [1:0] s_parity_mode,
            input logic       s_tx_start,
            input logic       s_tx_busy,
            input logic       s_tx_done,
            input logic       s_tx_line
        );
            din         = s_din;
            parity_mode = s_parity_mode;
            tx_start    = s_tx_start;
            tx_busy     = s_tx_busy;
            tx_done     = s_tx_done;
            tx_line     = s_tx_line;
            -> sample_event;
        endfunction

        function real get_coverage();
            return cg_uart.get_inst_coverage();
        endfunction

    endclass

endpackage
