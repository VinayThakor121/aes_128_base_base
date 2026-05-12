// top.v
// Top-level controller for the AES-UART system on Basys 3 (Artix-7 / 100 MHz).
//
// Workflow
//  1. Host PC sends 176 ASCII-hex bytes over UART:
//       bytes   0..31  – 128-bit plaintext
//       bytes  32..63  – 128-bit AES-128 key
//       bytes  64..111 – 192-bit AES-192 key
//       bytes 112..175 – 256-bit AES-256 key
//
//  2. packet_parser assembles the four values and pulses packet_valid.
//
//  3. AES_Encrypt / AES_Decrypt instances are purely combinational; outputs
//     are stable one propagation delay after the parser registers update.
//
//  4. response_tx latches the six results and transmits 270 ASCII-hex bytes:
//       AES128_ENC:<32 hex>\r\n
//       AES192_ENC:<32 hex>\r\n
//       AES256_ENC:<32 hex>\r\n
//       AES128_DEC:<32 hex>\r\n
//       AES192_DEC:<32 hex>\r\n
//       AES256_DEC:<32 hex>\r\n

module top (
    input  wire clk,      // 100 MHz system clock (W5 on Basys 3)
    input  wire rst,      // Active-high reset – BTNC (T18 on Basys 3)
    input  wire uart_rx,  // USB-UART RX into FPGA  (B16 on Basys 3)
    output wire uart_tx   // USB-UART TX from FPGA  (A16 on Basys 3)
);

// -------------------------------------------------------------------------
// UART RX → parser
// -------------------------------------------------------------------------
wire [7:0] rx_byte;
wire       rx_valid;

uart_rx #(
    .CLK_FREQ (100_000_000),
    .BAUD_RATE(115200)
) u_rx (
    .clk       (clk),
    .rst       (rst),
    .rx        (uart_rx),
    .data_out  (rx_byte),
    .data_valid(rx_valid)
);

// -------------------------------------------------------------------------
// Packet parser – assembles plaintext and three keys
// -------------------------------------------------------------------------
wire [127:0] plaintext;
wire [127:0] key128;
wire [191:0] key192;
wire [255:0] key256;
wire         packet_valid;

packet_parser u_parser (
    .clk         (clk),
    .rst         (rst),
    .rx_byte     (rx_byte),
    .rx_valid    (rx_valid),
    .plaintext   (plaintext),
    .key128      (key128),
    .key192      (key192),
    .key256      (key256),
    .packet_valid(packet_valid)
);

// -------------------------------------------------------------------------
// AES encryption  (purely combinational – results valid when inputs stable)
// -------------------------------------------------------------------------
wire [127:0] enc128, enc192, enc256;

AES_Encrypt                  u_enc128 (.in(plaintext), .key(key128), .out(enc128));
AES_Encrypt #(192, 12, 6)    u_enc192 (.in(plaintext), .key(key192), .out(enc192));
AES_Encrypt #(256, 14, 8)    u_enc256 (.in(plaintext), .key(key256), .out(enc256));

// -------------------------------------------------------------------------
// AES decryption  (decrypt the ciphertexts just produced)
// -------------------------------------------------------------------------
wire [127:0] dec128, dec192, dec256;

AES_Decrypt                  u_dec128 (.in(enc128), .key(key128), .out(dec128));
AES_Decrypt #(192, 12, 6)    u_dec192 (.in(enc192), .key(key192), .out(dec192));
AES_Decrypt #(256, 14, 8)    u_dec256 (.in(enc256), .key(key256), .out(dec256));

// -------------------------------------------------------------------------
// UART TX ← response transmitter
// -------------------------------------------------------------------------
wire [7:0] tx_byte;
wire       tx_send;
wire       tx_busy;

uart_tx #(
    .CLK_FREQ (100_000_000),
    .BAUD_RATE(115200)
) u_tx (
    .clk    (clk),
    .rst    (rst),
    .data_in(tx_byte),
    .send   (tx_send),
    .tx     (uart_tx),
    .busy   (tx_busy)
);

response_tx u_resp (
    .clk    (clk),
    .rst    (rst),
    .start  (packet_valid),
    .enc128 (enc128),
    .enc192 (enc192),
    .enc256 (enc256),
    .dec128 (dec128),
    .dec192 (dec192),
    .dec256 (dec256),
    .tx_byte(tx_byte),
    .tx_send(tx_send),
    .tx_busy(tx_busy),
    .done   (          ) // unused at top level
);

endmodule
