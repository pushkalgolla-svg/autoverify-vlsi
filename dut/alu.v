`timescale 1ns / 1ps

module alu (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [1:0] op,       // 2'b00: ADD, 2'b01: SUB, 2'b10: AND, 2'b11: OR
    output reg  [7:0] result,
    output reg        carry,
    output reg        zero
);

    always @(*) begin
        carry  = 1'b0;
        result = 8'h00;
        case (op)
            2'b00: {carry, result} = a + b;
            // FIXED: SUB opcode (2'b01) now performs subtraction (a - b)
            2'b01: {carry, result} = a - b;
            2'b10: result = a & b;
            2'b11: result = a | b;
            default: result = 8'h00;
        endcase
        zero = (result == 8'h00);
    end

endmodule
