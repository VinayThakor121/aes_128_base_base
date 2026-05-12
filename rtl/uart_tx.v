// uart_tx.v
// 8N1 UART transmitter.
//
// Parameters
//   CLK_FREQ  – system clock frequency in Hz  (default 100 MHz)
//   BAUD_RATE – desired baud rate             (default 115 200)
//
// Inputs
//   data_in – byte to transmit
//   send    – assert for one cycle when data_in is valid; ignored while busy
//
// Outputs
//   tx   – serial output line (idle-high)
//   busy – high while a transmission is in progress

module uart_tx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data_in,
    input  wire       send,
    output reg        tx,
    output reg        busy
);

localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 868 @ 100 MHz / 115200

localparam S_IDLE  = 2'd0;
localparam S_START = 2'd1;
localparam S_DATA  = 2'd2;
localparam S_STOP  = 2'd3;

reg [1:0]  state;
reg [15:0] clk_cnt;
reg [2:0]  bit_idx;
reg [7:0]  tx_data;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state   <= S_IDLE;
        tx      <= 1'b1;
        busy    <= 1'b0;
        clk_cnt <= 16'd0;
        bit_idx <= 3'd0;
        tx_data <= 8'd0;
    end else begin
        case (state)
            S_IDLE: begin
                tx   <= 1'b1;
                busy <= 1'b0;
                if (send) begin
                    tx_data <= data_in;
                    busy    <= 1'b1;
                    clk_cnt <= 16'd0;
                    state   <= S_START;
                end
            end

            S_START: begin
                tx <= 1'b0; // start bit
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    state   <= S_DATA;
                end else
                    clk_cnt <= clk_cnt + 1'b1;
            end

            S_DATA: begin
                tx <= tx_data[bit_idx]; // LSB first
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt <= 16'd0;
                    if (bit_idx == 3'd7)
                        state <= S_STOP;
                    else
                        bit_idx <= bit_idx + 1'b1;
                end else
                    clk_cnt <= clk_cnt + 1'b1;
            end

            S_STOP: begin
                tx <= 1'b1; // stop bit
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    busy    <= 1'b0;
                    clk_cnt <= 16'd0;
                    state   <= S_IDLE;
                end else
                    clk_cnt <= clk_cnt + 1'b1;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
