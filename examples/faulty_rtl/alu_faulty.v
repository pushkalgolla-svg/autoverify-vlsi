`timescale 1ns / 1ps

/**
 * DELIBERATELY FAULTY Parameterized ALU (Demonstration Copy)
 * Injected Defect: Inverted subtraction borrow condition on line 34:
 *   carry = (a > b); // BUG: Inverted logic, causes borrow flag failure when a < b
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
                carry  = (a > b); // INJECTED DEFECT: Inverted comparison condition!
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