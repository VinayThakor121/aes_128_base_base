// packet_parser.v
// Receives 176 ASCII-hex bytes from the UART and assembles:
//   plaintext  [127:0]  –  bytes  0..31   (32 hex chars = 128 bits)
//   key128     [127:0]  –  bytes 32..63   (32 hex chars = 128 bits)
//   key192     [191:0]  –  bytes 64..111  (48 hex chars = 192 bits)
//   key256     [255:0]  –  bytes 112..175 (64 hex chars = 256 bits)
//
// packet_valid is a single-cycle strobe asserted when the 176th byte has
// been stored and all four output registers hold their final values.
//
// The parser accepts lower-case and upper-case hex digits.
// Non-hex characters are mapped to nibble 0 (no hard error).

module packet_parser (
    input  wire         clk,
    input  wire         rst,
    input  wire [7:0]   rx_byte,
    input  wire         rx_valid,
    output reg  [127:0] plaintext,
    output reg  [127:0] key128,
    output reg  [191:0] key192,
    output reg  [255:0] key256,
    output reg          packet_valid
);

// Packet byte boundaries
localparam TOTAL_BYTES = 176;
localparam PT_LAST     = 31;   // bytes 0..31   → plaintext
localparam K128_LAST   = 63;   // bytes 32..63  → key128
localparam K192_LAST   = 111;  // bytes 64..111 → key192
// bytes 112..175 → key256

reg [7:0] byte_cnt; // 0..175

// Convert an ASCII hex character to a 4-bit nibble.
// Handles '0'-'9', 'a'-'f', 'A'-'F'.
// Trick: bit 6 of the ASCII code distinguishes digits (0) from letters (1).
//   digits  ('0'=0x30 .. '9'=0x39): nibble = c[3:0]
//   letters ('A'=0x41 .. 'F'=0x46,
//            'a'=0x61 .. 'f'=0x66): nibble = c[3:0] + 9
//   (for hex letters c[3:0] is 1..6, so +9 yields 10..15)
function [3:0] hex_to_nib;
    input [7:0] c;
    begin
        hex_to_nib = c[6] ? (c[3:0] + 4'd9) : c[3:0];
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        byte_cnt     <= 8'd0;
        packet_valid <= 1'b0;
        plaintext    <= 128'd0;
        key128       <= 128'd0;
        key192       <= 192'd0;
        key256       <= 256'd0;
    end else begin
        packet_valid <= 1'b0; // default: deassert each cycle

        if (rx_valid) begin
            // Shift the incoming nibble into the appropriate register (MSB first)
            if (byte_cnt <= PT_LAST) begin
                plaintext <= {plaintext[123:0], hex_to_nib(rx_byte)};
            end else if (byte_cnt <= K128_LAST) begin
                key128    <= {key128[123:0],    hex_to_nib(rx_byte)};
            end else if (byte_cnt <= K192_LAST) begin
                key192    <= {key192[187:0],    hex_to_nib(rx_byte)};
            end else begin
                key256    <= {key256[251:0],    hex_to_nib(rx_byte)};
            end

            if (byte_cnt == TOTAL_BYTES - 1) begin
                byte_cnt     <= 8'd0;
                packet_valid <= 1'b1;
            end else begin
                byte_cnt <= byte_cnt + 1'b1;
            end
        end
    end
end

endmodule
