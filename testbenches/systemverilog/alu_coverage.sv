// =============================================================================
// AutoVerify-VLSI: SystemVerilog IEEE 1800 Reference Functional Coverage Model
// Module: alu_coverage.sv
// Target: Commercial EDA Simulators (Synopsys VCS, Cadence Xcelium, Siemens Questa)
// Note  : For open-source CI (Icarus Verilog), portable procedural coverage in
//         testbenches/tb_alu.v is executed.
// =============================================================================

`timescale 1ns / 1ps

package alu_cov_pkg;

    class alu_coverage_model #(parameter int DATA_WIDTH = 8);

        // Transaction variables sampled by covergroup
        logic [DATA_WIDTH-1:0] a;
        logic [DATA_WIDTH-1:0] b;
        logic [1:0]            op;
        logic [DATA_WIDTH-1:0] result;
        logic                  carry;
        logic                  zero;

        // IEEE 1800 Covergroup Specification
        covergroup cg_alu @(posedge sample_event);
            option.per_instance = 1;
            option.name = $sformatf("cg_alu_w%0d", DATA_WIDTH);

            // Operation Coverage
            cp_op: coverpoint op {
                bins op_add = {2'b00};
                bins op_sub = {2'b01};
                bins op_and = {2'b10};
                bins op_or  = {2'b11};
            }

            // Operand A Corner Cases & Patterns
            cp_operand_a: coverpoint a {
                bins val_zero     = {'0};
                bins val_all_ones = {'1};
                bins val_msb_only = {1'b1 << (DATA_WIDTH-1)};
                bins val_lsb_only = {'d1};
                bins val_mid      = { [1 : (1 << (DATA_WIDTH-1))-1] };
            }

            // Operand B Corner Cases & Patterns
            cp_operand_b: coverpoint b {
                bins val_zero     = {'0};
                bins val_all_ones = {'1};
                bins val_msb_only = {1'b1 << (DATA_WIDTH-1)};
                bins val_lsb_only = {'d1};
                bins val_mid      = { [1 : (1 << (DATA_WIDTH-1))-1] };
            }

            // Status Flag Coverage
            cp_carry: coverpoint carry {
                bins carry_clear = {1'b0};
                bins carry_set   = {1'b1};
            }

            cp_zero: coverpoint zero {
                bins zero_clear = {1'b0};
                bins zero_set   = {1'b1};
            }

            // Comprehensive Cross Coverage: Operations x Corner Operands
            cross_op_a_b: cross cp_op, cp_operand_a, cp_operand_b {
                // Focus on corner-case intersections across all 4 opcodes
                bins add_max_max = binsof(cp_op.op_add) && binsof(cp_operand_a.val_all_ones) && binsof(cp_operand_b.val_all_ones);
                bins add_max_min = binsof(cp_op.op_add) && binsof(cp_operand_a.val_all_ones) && binsof(cp_operand_b.val_zero);
                bins add_min_min = binsof(cp_op.op_add) && binsof(cp_operand_a.val_zero)     && binsof(cp_operand_b.val_zero);
                bins sub_max_max = binsof(cp_op.op_sub) && binsof(cp_operand_a.val_all_ones) && binsof(cp_operand_b.val_all_ones);
                bins sub_min_max = binsof(cp_op.op_sub) && binsof(cp_operand_a.val_zero)     && binsof(cp_operand_b.val_all_ones);
                bins sub_max_min = binsof(cp_op.op_sub) && binsof(cp_operand_a.val_all_ones) && binsof(cp_operand_b.val_zero);
                bins and_corners = binsof(cp_op.op_and) && (binsof(cp_operand_a.val_all_ones) || binsof(cp_operand_a.val_zero));
                bins or_corners  = binsof(cp_op.op_or)  && (binsof(cp_operand_a.val_all_ones) || binsof(cp_operand_a.val_zero));
            }

            // Boundary Cross: Opcode x Carry Flag
            cross_op_carry: cross cp_op, cp_carry {
                bins add_overflow = binsof(cp_op.op_add) && binsof(cp_carry.carry_set);
                bins add_no_ovf   = binsof(cp_op.op_add) && binsof(cp_carry.carry_clear);
                bins sub_borrow   = binsof(cp_op.op_sub) && binsof(cp_carry.carry_set);
                bins sub_no_borr  = binsof(cp_op.op_sub) && binsof(cp_carry.carry_clear);
                ignore_bins logic_carry = binsof(cp_op.op_and, cp_op.op_or) && binsof(cp_carry.carry_set);
            }

            // Boundary Cross: Opcode x Zero Flag
            cross_op_zero: cross cp_op, cp_zero {
                bins zero_res_add = binsof(cp_op.op_add) && binsof(cp_zero.zero_set);
                bins zero_res_sub = binsof(cp_op.op_sub) && binsof(cp_zero.zero_set);
                bins zero_res_and = binsof(cp_op.op_and) && binsof(cp_zero.zero_set);
                bins zero_res_or  = binsof(cp_op.op_or)  && binsof(cp_zero.zero_set);
            }
        endgroup

        event sample_event;

        function new();
            cg_alu = new();
        endfunction

        function void sample(
            input logic [DATA_WIDTH-1:0] sample_a,
            input logic [DATA_WIDTH-1:0] sample_b,
            input logic [1:0]            sample_op,
            input logic [DATA_WIDTH-1:0] sample_result,
            input logic                  sample_carry,
            input logic                  sample_zero
        );
            a      = sample_a;
            b      = sample_b;
            op     = sample_op;
            result = sample_result;
            carry  = sample_carry;
            zero   = sample_zero;
            -> sample_event;
        endfunction

        function real get_coverage();
            return cg_alu.get_inst_coverage();
        endfunction

    endclass

endpackage
