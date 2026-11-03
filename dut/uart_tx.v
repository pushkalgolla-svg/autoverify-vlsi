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
                    // INJECTED BUG: Ends stop bit prematurely at clk_count == 2
                    // instead of waiting for full CLKS_PER_BIT - 1!
                    // This causes framing errors on back-to-back transmissions.
                    if (clk_count < 2) begin
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
