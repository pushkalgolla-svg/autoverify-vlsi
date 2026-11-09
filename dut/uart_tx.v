`timescale 1ns / 1ps

/**
 * UART Transmitter with Configurable Baud Rate and Latched Parity
 *
 * Parameters:
 *   CLKS_PER_BIT : Clock cycles per baud period (default 10 for simulation)
 *
 * Parity Modes (parity_mode):
 *   2'b00 : No Parity
 *   2'b01 : Odd Parity
 *   2'b10 : Even Parity
 *   2'b11 : Reserved / Unsupported (safely treated as No Parity)
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
    input  wire [1:0] parity_mode, // 2'b00: None, 2'b01: Odd, 2'b10: Even, 2'b11: Reserved
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
    reg [1:0]  tx_parity_mode; // Latched parity mode throughout transmission
    reg        parity_bit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= STATE_IDLE;
            clk_count      <= 16'd0;
            bit_index      <= 3'd0;
            tx_data        <= 8'd0;
            tx_parity_mode <= 2'b00;
            parity_bit     <= 1'b0;
            tx             <= 1'b1; // Idle UART line is HIGH
            tx_busy        <= 1'b0;
            tx_done        <= 1'b0;
        end else begin
            tx_done <= 1'b0; // Default single-cycle pulse

            case (state)
                STATE_IDLE: begin
                    tx        <= 1'b1;
                    tx_busy   <= 1'b0;
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;

                    if (tx_start) begin
                        tx_data        <= din;
                        tx_parity_mode <= parity_mode; // Latch parity mode on start
                        tx_busy        <= 1'b1;
                        tx             <= 1'b0;        // Drive Start bit (LOW)
                        state          <= STATE_START;

                        if (parity_mode == 2'b01)
                            parity_bit <= ~(^din); // Odd parity
                        else if (parity_mode == 2'b10)
                            parity_bit <= ^din;    // Even parity
                        else
                            parity_bit <= 1'b0;    // 2'b00 (None) or 2'b11 (Reserved/Unsupported)
                    end
                end

                STATE_START: begin
                    tx <= 1'b0;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        tx        <= tx_data[0]; // Drive first data bit
                        state     <= STATE_DATA;
                    end
                end

                STATE_DATA: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        if (bit_index < 3'd7) begin
                            bit_index <= bit_index + 1'b1;
                            tx        <= tx_data[bit_index + 1];
                        end else begin
                            bit_index <= 3'd0;
                            // Supported parity: 2'b01 (Odd), 2'b10 (Even).
                            // 2'b00 (None) and unsupported 2'b11 safely proceed to STOP state.
                            if (tx_parity_mode == 2'b01 || tx_parity_mode == 2'b10) begin
                                tx    <= parity_bit;
                                state <= STATE_PARITY;
                            end else begin
                                tx    <= 1'b1; // Drive Stop bit (HIGH)
                                state <= STATE_STOP;
                            end
                        end
                    end
                end

                STATE_PARITY: begin
                    tx <= parity_bit;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        tx        <= 1'b1; // Drive Stop bit (HIGH)
                        state     <= STATE_STOP;
                    end
                end

                STATE_STOP: begin
                    tx <= 1'b1; // Stop bit is HIGH
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1'b1;
                    end else begin
                        clk_count <= 16'd0;
                        tx_done   <= 1'b1;
                        tx_busy   <= 1'b0;
                        state     <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
