`timescale 1ns / 1ps

/**
 * Parameterized Synchronous FIFO with Status Flags and Error Detection
 * 
 * Parameters:
 *   DATA_WIDTH : Width of data words (default 8)
 *   DEPTH      : Number of words in FIFO (default 16)
 *
 * Ports:
 *   clk, rst_n : Clock and active-low asynchronous reset
 *   wr_en, din : Write enable and input data
 *   rd_en, dout: Read enable and output data
 *   full, empty: Status flags
 *   overflow   : Error flag asserted if write attempted when full
 *   underflow  : Error flag asserted if read attempted when empty
 *   count      : Current fill level of FIFO
 */

module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] dout,
    output wire                  full,
    output wire                  empty,
    output reg                   overflow,
    output reg                   underflow,
    output reg  [$clog2(DEPTH):0] count
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    // Memory array
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Read and Write pointers
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    assign empty = (count == 0);
    assign full  = (count == DEPTH);

    // Synchronous Write & Read Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr    <= {ADDR_WIDTH{1'b0}};
            rd_ptr    <= {ADDR_WIDTH{1'b0}};
            dout      <= {DATA_WIDTH{1'b0}};
            count     <= 0;
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end else begin
            // Reset pulse error flags each cycle unless re-triggered
            overflow  <= 1'b0;
            underflow <= 1'b0;

            case ({wr_en, rd_en})
                2'b10: begin // Write only
                    if (!full) begin
                        mem[wr_ptr] <= din;
                        wr_ptr      <= wr_ptr + 1'b1;
                        count       <= count + 1'b1;
                    end else begin
                        overflow    <= 1'b1;
                    end
                end

                2'b01: begin // Read only
                    if (!empty) begin
                        dout        <= mem[rd_ptr];
                        rd_ptr      <= rd_ptr + 1'b1;
                        count       <= count - 1'b1;
                    end else begin
                        underflow   <= 1'b1;
                    end
                end

                2'b11: begin // Simultaneous Write and Read
                    // Handled correctly: count unchanged, write and read both advance
                    // BUT: INJECTED BUG when FIFO is empty:
                    // If empty, reading should be disallowed and count should increment by 1.
                    // BUG: We allow reading uninitialized memory and decrement count, corrupting the pointer!
                    mem[wr_ptr] <= din;
                    wr_ptr      <= wr_ptr + 1'b1;
                    dout        <= mem[rd_ptr];
                    rd_ptr      <= rd_ptr + 1'b1;
                    if (empty) begin
                        // Corner-case bug: underflow is asserted, but count wraps negatively
                        underflow <= 1'b1;
                        count     <= count - 1'b1; // BUG: Underflows the counter when empty!
                    end
                end

                default: begin
                    // No operation
                end
            endcase
        end
    end

endmodule
