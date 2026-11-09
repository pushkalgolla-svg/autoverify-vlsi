`timescale 1ns / 1ps

/**
 * Parameterized Arithmetic Logic Unit (ALU)
 *
 * Parameters:
 *   DATA_WIDTH : Width of operands and result (default 8)
 *
 * Opcodes:
 *   2'b00 : ADD (carry = overflow flag)
 *   2'b01 : SUB (carry = borrow flag, 1 if a < b)
 *   2'b10 : AND (bitwise AND, carry = 0)
 *   2'b11 : OR  (bitwise OR,  carry = 0)
 */

module alu #(
    parameter DATA_WIDTH = 8
) (
    input  wire [DATA_WIDTH-1:0] a,
    input  wire [DATA_WIDTH-1:0] b,
    input  wire [1:0]            op,
    output reg  [DATA_WIDTH-1:0] result,
    output reg                   carry,
    output reg                   zero
);

    always @(*) begin
        carry  = 1'b0;
        result = {DATA_WIDTH{1'b0}};
        case (op)
            2'b00: {carry, result} = a + b;
            2'b01: begin
                result = a - b;
                carry  = (a < b); // Explicit borrow indicator: 1 if underflow (a < b)
            end
            2'b10: result = a & b;
            2'b11: result = a | b;
            default: begin
                result = {DATA_WIDTH{1'b0}};
                carry  = 1'b0;
            end
        endcase
        zero = (result == {DATA_WIDTH{1'b0}});
    end

endmodule
