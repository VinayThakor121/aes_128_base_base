// uart_rx.v
// 8N1 UART receiver with two-flip-flop input synchroniser.
//
// Parameters
//   CLK_FREQ  – system clock frequency in Hz  (default 100 MHz)
//   BAUD_RATE – desired baud rate             (default 115 200)
//
// Outputs
//   data_out  – received byte (valid when data_valid is high for one cycle)
//   data_valid – single-cycle strobe when a new byte has been captured

module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_valid
);

localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // 868 @ 100 MHz / 115200

localparam S_IDLE  = 2'd0;
localparam S_START = 2'd1;
localparam S_DATA  = 2'd2;
localparam S_STOP  = 2'd3;

reg [1:0]  state;
reg [15:0] clk_cnt;
reg [2:0]  bit_idx;
reg [7:0]  rx_shift;
reg        rx_d1, rx_d2; // two-FF synchroniser

// Synchronise the async RX input
always @(posedge clk) begin
    rx_d1 <= rx;
    rx_d2 <= rx_d1;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state      <= S_IDLE;
        clk_cnt    <= 16'd0;
        bit_idx    <= 3'd0;
        rx_shift   <= 8'd0;
        data_out   <= 8'd0;
        data_valid <= 1'b0;
    end else begin
        data_valid <= 1'b0; // default: deassert each cycle

        case (state)
            S_IDLE: begin
                clk_cnt <= 16'd0;
                bit_idx <= 3'd0;
                if (rx_d2 == 1'b0)   // falling edge → start bit
                    state <= S_START;
            end

            // Sample in the middle of the start bit to confirm it is still low
            S_START: begin
                if (clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                    clk_cnt <= 16'd0;
                    if (rx_d2 == 1'b0)
                        state <= S_DATA;
                    else
                        state <= S_IDLE; // glitch – abort
                end else
                    clk_cnt <= clk_cnt + 1'b1;
            end

            // Sample each data bit at the centre of its bit period
            S_DATA: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    clk_cnt            <= 16'd0;
                    rx_shift[bit_idx]  <= rx_d2; // LSB first
                    if (bit_idx == 3'd7) begin
                        bit_idx <= 3'd0;
                        state   <= S_STOP;
                    end else
                        bit_idx <= bit_idx + 1'b1;
                end else
                    clk_cnt <= clk_cnt + 1'b1;
            end

            S_STOP: begin
                if (clk_cnt == CLKS_PER_BIT - 1) begin
                    data_out   <= rx_shift;
                    data_valid <= 1'b1;
                    clk_cnt    <= 16'd0;
                    state      <= S_IDLE;
                end else
                    clk_cnt <= clk_cnt + 1'b1;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
