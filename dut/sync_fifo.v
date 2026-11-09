`timescale 1ns / 1ps

/**
 * Parameterized Synchronous FIFO with Status Flags and Error Detection
 * 
 * Parameters:
 *   DATA_WIDTH : Width of data words (default 8)
 *   DEPTH      : Number of words in FIFO (default 16, supports DEPTH >= 1)
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
    input  wire                                   clk,
    input  wire                                   rst_n,
    input  wire                                   wr_en,
    input  wire [DATA_WIDTH-1:0]                  din,
    input  wire                                   rd_en,
    output reg  [DATA_WIDTH-1:0]                  dout,
    output wire                                   full,
    output wire                                   empty,
    output reg                                    overflow,
    output reg                                    underflow,
    output reg  [$clog2(DEPTH < 2 ? 2 : DEPTH):0] count
);

    localparam ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam COUNT_WIDTH = $clog2(DEPTH < 2 ? 2 : DEPTH) + 1;

    // Memory array
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Read and Write pointers
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;

    assign empty = (count == {COUNT_WIDTH{1'b0}});
    assign full  = (count == DEPTH);

    // Synchronous Write & Read Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr    <= {ADDR_WIDTH{1'b0}};
            rd_ptr    <= {ADDR_WIDTH{1'b0}};
            dout      <= {DATA_WIDTH{1'b0}};
            count     <= {COUNT_WIDTH{1'b0}};
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end else begin
            // Reset single-cycle pulse error flags unless re-triggered
            overflow  <= 1'b0;
            underflow <= 1'b0;

            case ({wr_en, rd_en})
                2'b10: begin // Write only
                    if (!full) begin
                        mem[wr_ptr] <= din;
                        wr_ptr      <= (wr_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
                        count       <= count + 1'b1;
                    end else begin
                        overflow    <= 1'b1;
                    end
                end

                2'b01: begin // Read only
                    if (!empty) begin
                        dout        <= mem[rd_ptr];
                        rd_ptr      <= (rd_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;
                        count       <= count - 1'b1;
                    end else begin
                        underflow   <= 1'b1;
                    end
                end

                2'b11: begin // Simultaneous Write and Read
                    if (empty) begin
                        // FIFO empty: Write succeeds, read fails with underflow
                        mem[wr_ptr] <= din;
                        wr_ptr      <= (wr_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
                        count       <= count + 1'b1;
                        underflow   <= 1'b1;
                    end else if (full) begin
                        // FIFO full: Read succeeds, write fails with overflow
                        dout        <= mem[rd_ptr];
                        rd_ptr      <= (rd_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;
                        count       <= count - 1'b1;
                        overflow    <= 1'b1;
                    end else begin
                        // Normal simultaneous write and read: count remains unchanged
                        mem[wr_ptr] <= din;
                        wr_ptr      <= (wr_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
                        dout        <= mem[rd_ptr];
                        rd_ptr      <= (rd_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;
                    end
                end

                default: begin
                    // No operation (2'b00)
                end
            endcase
        end
    end

endmodule
