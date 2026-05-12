// response_tx.v
// Serialises six 128-bit AES results over UART as six labelled ASCII-hex lines.
//
// Output format (270 bytes total, 6 × 45 bytes):
//   AES128_ENC:<32 hex chars>\r\n
//   AES192_ENC:<32 hex chars>\r\n
//   AES256_ENC:<32 hex chars>\r\n
//   AES128_DEC:<32 hex chars>\r\n
//   AES192_DEC:<32 hex chars>\r\n
//   AES256_DEC:<32 hex chars>\r\n
//
// Interface with uart_tx:
//   Presents tx_byte + one-cycle tx_send pulse whenever tx_busy is low.
//   The module waits for tx_busy to deassert before submitting the next byte.
//
// done is a single-cycle strobe when the last byte has been handed to the TX
// FIFO (physical transmission may still be in progress).

module response_tx (
    input  wire        clk,
    input  wire        rst,
    // Trigger: assert for one cycle with stable AES outputs
    input  wire        start,
    // Six AES results to transmit
    input  wire [127:0] enc128,
    input  wire [127:0] enc192,
    input  wire [127:0] enc256,
    input  wire [127:0] dec128,
    input  wire [127:0] dec192,
    input  wire [127:0] dec256,
    // UART TX interface
    output reg  [7:0]  tx_byte,
    output reg         tx_send,
    input  wire        tx_busy,
    // Completion strobe
    output reg         done
);

// Line layout: 11-char label + 32-char hex + \r + \n = 45 chars
localparam LABEL_LEN     = 11;
localparam HEX_LEN       = 32;
localparam BYTES_PER_LINE = 45; // LABEL_LEN + HEX_LEN + 2
localparam NUM_LINES     = 6;

localparam S_IDLE = 2'd0;
localparam S_SEND = 2'd1;
localparam S_DONE = 2'd2;

reg [1:0] state;
reg [2:0] line_idx;    // 0..5
reg [5:0] pos_in_line; // 0..44

// Latched copies of the AES results (captured on 'start')
reg [127:0] r_enc128, r_enc192, r_enc256;
reg [127:0] r_dec128, r_dec192, r_dec256;

// -----------------------------------------------------------------------
// Combinational data mux – select the result for the current line
// -----------------------------------------------------------------------
reg [127:0] cur_data;

always @(*) begin
    case (line_idx)
        3'd0:    cur_data = r_enc128;
        3'd1:    cur_data = r_enc192;
        3'd2:    cur_data = r_enc256;
        3'd3:    cur_data = r_dec128;
        3'd4:    cur_data = r_dec192;
        default: cur_data = r_dec256;
    endcase
end

// -----------------------------------------------------------------------
// Helper functions
// -----------------------------------------------------------------------

// Convert 4-bit nibble to lower-case ASCII hex character
function [7:0] nib2asc;
    input [3:0] n;
    begin
        nib2asc = (n < 4'd10) ? (8'h30 + {4'h0, n})
                               : (8'h61 + {4'h0, n} - 8'd10);
    end
endfunction

// Return the ASCII byte at position 'pos' (0..10) within a line's label.
// Labels are stored as 88-bit (11-char) string literals; byte 0 is MSB.
function [7:0] get_label_byte;
    input [2:0] line;
    input [3:0] pos;   // 0..10
    reg [87:0]  lbl;
    reg [6:0]   base;
    begin
        case (line)
            3'd0: lbl = "AES128_ENC:";
            3'd1: lbl = "AES192_ENC:";
            3'd2: lbl = "AES256_ENC:";
            3'd3: lbl = "AES128_DEC:";
            3'd4: lbl = "AES192_DEC:";
            default: lbl = "AES256_DEC:";
        endcase
        // lbl[87:80]='A', lbl[79:72]='E', ..., lbl[7:0]=':'
        // Byte at position pos starts at bit (87 - pos*8)
        base = 7'd87 - {pos, 3'b000}; // pos * 8
        get_label_byte = lbl[base -: 8];
    end
endfunction

// Return the hex ASCII byte for nibble index nib_idx (0=MSN, 31=LSN)
// of a 128-bit data word.
function [7:0] get_hex_byte;
    input [127:0] data;
    input [4:0]   nib_idx; // 0..31
    reg [6:0]     base;
    begin
        // Bit base of nibble nib_idx: 127 - nib_idx*4
        base = 7'd127 - {nib_idx, 2'b00}; // nib_idx * 4
        get_hex_byte = nib2asc(data[base -: 4]);
    end
endfunction

// -----------------------------------------------------------------------
// Main state machine
// -----------------------------------------------------------------------
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state       <= S_IDLE;
        line_idx    <= 3'd0;
        pos_in_line <= 6'd0;
        tx_byte     <= 8'd0;
        tx_send     <= 1'b0;
        done        <= 1'b0;
        r_enc128    <= 128'd0;
        r_enc192    <= 128'd0;
        r_enc256    <= 128'd0;
        r_dec128    <= 128'd0;
        r_dec192    <= 128'd0;
        r_dec256    <= 128'd0;
    end else begin
        tx_send <= 1'b0; // default: deassert each cycle
        done    <= 1'b0;

        case (state)
            // -----------------------------------------------------------------
            S_IDLE: begin
                if (start) begin
                    // Latch AES results (combinational outputs are stable now)
                    r_enc128    <= enc128;
                    r_enc192    <= enc192;
                    r_enc256    <= enc256;
                    r_dec128    <= dec128;
                    r_dec192    <= dec192;
                    r_dec256    <= dec256;
                    line_idx    <= 3'd0;
                    pos_in_line <= 6'd0;
                    state       <= S_SEND;
                end
            end

            // -----------------------------------------------------------------
            // Send one byte per TX-idle opportunity.
            // !tx_send ensures we wait one cycle after asserting send before
            // checking tx_busy again (tx_busy rises one cycle after send).
            S_SEND: begin
                if (!tx_busy && !tx_send) begin
                    // Compute current byte
                    if (pos_in_line < LABEL_LEN) begin
                        tx_byte <= get_label_byte(line_idx, pos_in_line[3:0]);
                    end else if (pos_in_line < LABEL_LEN + HEX_LEN) begin
                        tx_byte <= get_hex_byte(cur_data,
                                                pos_in_line[4:0] - 5'd11);
                    end else if (pos_in_line == LABEL_LEN + HEX_LEN) begin
                        tx_byte <= 8'h0d; // '\r'
                    end else begin
                        tx_byte <= 8'h0a; // '\n'
                    end

                    tx_send <= 1'b1;

                    // Advance position / line counters
                    if (pos_in_line == BYTES_PER_LINE - 1) begin
                        pos_in_line <= 6'd0;
                        if (line_idx == NUM_LINES - 1)
                            state <= S_DONE;
                        else
                            line_idx <= line_idx + 1'b1;
                    end else begin
                        pos_in_line <= pos_in_line + 1'b1;
                    end
                end
            end

            // -----------------------------------------------------------------
            S_DONE: begin
                done  <= 1'b1;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
