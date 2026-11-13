// =============================================================================
// AutoVerify-VLSI: SystemVerilog IEEE 1800 Reference Functional Coverage Model
// Module: fifo_coverage.sv
// Target: Commercial EDA Simulators (Synopsys VCS, Cadence Xcelium, Siemens Questa)
// Note  : For open-source CI (Icarus Verilog), portable procedural coverage in
//         testbenches/tb_sync_fifo.v is executed.
// =============================================================================

`timescale 1ns / 1ps

package fifo_cov_pkg;

    class fifo_coverage_model #(parameter int DATA_WIDTH = 8, parameter int DEPTH = 16);

        localparam int COUNT_WIDTH = $clog2(DEPTH < 2 ? 2 : DEPTH) + 1;

        // Transaction variables sampled by covergroup
        logic                   wr_en;
        logic                   rd_en;
        logic [DATA_WIDTH-1:0]  din;
        logic [DATA_WIDTH-1:0]  dout;
        logic                   full;
        logic                   empty;
        logic                   overflow;
        logic                   underflow;
        logic [COUNT_WIDTH-1:0] count;

        event sample_event;

        // IEEE 1800 Covergroup Specification
        covergroup cg_fifo @(posedge sample_event);
            option.per_instance = 1;
            option.name = $sformatf("cg_fifo_d%0d_w%0d", DEPTH, DATA_WIDTH);

            // Operation Mode Coverage
            cp_wr_en: coverpoint wr_en {
                bins idle  = {1'b0};
                bins write = {1'b1};
            }

            cp_rd_en: coverpoint rd_en {
                bins idle = {1'b0};
                bins read = {1'b1};
            }

            // Occupancy Boundary Coverage
            cp_count: coverpoint count {
                bins empty_state        = {0};
                bins single_item_state  = {1};
                bins almost_full_state  = {DEPTH > 1 ? DEPTH - 1 : 1};
                bins full_state         = {DEPTH};
                bins intermediate_state = { [2 : (DEPTH > 2 ? DEPTH - 2 : 1)] };
            }

            // Flag State Coverage
            cp_empty_flag: coverpoint empty {
                bins not_empty = {1'b0};
                bins is_empty  = {1'b1};
            }

            cp_full_flag: coverpoint full {
                bins not_full = {1'b0};
                bins is_full  = {1'b1};
            }

            cp_overflow: coverpoint overflow {
                bins no_overflow = {1'b0};
                bins had_overflow = {1'b1};
            }

            cp_underflow: coverpoint underflow {
                bins no_underflow = {1'b0};
                bins had_underflow = {1'b1};
            }

            // Simultaneous Read/Write Cross Coverage across Occupancy Levels
            cross_rw_occupancy: cross cp_wr_en, cp_rd_en, cp_count {
                bins simul_at_empty = binsof(cp_wr_en.write) && binsof(cp_rd_en.read) && binsof(cp_count.empty_state);
                bins simul_at_full  = binsof(cp_wr_en.write) && binsof(cp_rd_en.read) && binsof(cp_count.full_state);
                bins simul_at_inter = binsof(cp_wr_en.write) && binsof(cp_rd_en.read) && binsof(cp_count.intermediate_state);
                bins write_only     = binsof(cp_wr_en.write) && binsof(cp_rd_en.idle);
                bins read_only      = binsof(cp_wr_en.idle)  && binsof(cp_rd_en.read);
            }

            // Error Boundary Cross: Write on Full -> Overflow
            cross_wr_full_overflow: cross cp_wr_en, cp_full_flag, cp_overflow {
                bins ovf_triggered = binsof(cp_wr_en.write) && binsof(cp_full_flag.is_full) && binsof(cp_overflow.had_overflow);
            }

            // Error Boundary Cross: Read on Empty -> Underflow
            cross_rd_empty_underflow: cross cp_rd_en, cp_empty_flag, cp_underflow {
                bins unf_triggered = binsof(cp_rd_en.read) && binsof(cp_empty_flag.is_empty) && binsof(cp_underflow.had_underflow);
            }
        endgroup

        function new();
            cg_fifo = new();
        endfunction

        function void sample(
            input logic                   s_wr_en,
            input logic                   s_rd_en,
            input logic [DATA_WIDTH-1:0]  s_din,
            input logic [DATA_WIDTH-1:0]  s_dout,
            input logic                   s_full,
            input logic                   s_empty,
            input logic                   s_overflow,
            input logic                   s_underflow,
            input logic [COUNT_WIDTH-1:0] s_count
        );
            wr_en     = s_wr_en;
            rd_en     = s_rd_en;
            din       = s_din;
            dout      = s_dout;
            full      = s_full;
            empty     = s_empty;
            overflow  = s_overflow;
            underflow = s_underflow;
            count     = s_count;
            -> sample_event;
        endfunction

        function real get_coverage();
            return cg_fifo.get_inst_coverage();
        endfunction

    endclass

endpackage
