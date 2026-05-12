#!/usr/bin/env python3
"""
aes_uart_host.py
================
PC-side script for the AES-UART system running on Basys 3 FPGA.

Protocol
--------
Send  : 176 lower-case ASCII hex characters (no spaces / delimiters):
          chars   0..31  – 128-bit plaintext
          chars  32..63  – 128-bit AES-128 key
          chars  64..111 – 192-bit AES-192 key
          chars 112..175 – 256-bit AES-256 key

Receive: 6 lines, each terminated with \\r\\n:
          AES128_ENC:<32 hex chars>
          AES192_ENC:<32 hex chars>
          AES256_ENC:<32 hex chars>
          AES128_DEC:<32 hex chars>
          AES192_DEC:<32 hex chars>
          AES256_DEC:<32 hex chars>

Requirements
------------
    pip install pyserial

Usage
-----
    # Default NIST test vectors, auto-detect port:
    python aes_uart_host.py

    # Specify port explicitly:
    python aes_uart_host.py --port COM3          # Windows
    python aes_uart_host.py --port /dev/ttyUSB0  # Linux

    # Custom inputs:
    python aes_uart_host.py \\
        --port /dev/ttyUSB0 \\
        --plaintext 00112233445566778899aabbccddeeff \\
        --key128    000102030405060708090a0b0c0d0e0f \\
        --key192    000102030405060708090a0b0c0d0e0f1011121314151617 \\
        --key256    000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
"""

import argparse
import sys
import time

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("ERROR: pyserial is not installed.  Run:  pip install pyserial")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
BAUD_RATE      = 115200
PACKET_LEN     = 176   # bytes sent to FPGA
NUM_REPLY_LINES = 6    # lines expected back
REPLY_TIMEOUT   = 15   # seconds to wait for each line

# NIST FIPS-197 Appendix B / C test vectors
DEFAULT_PLAINTEXT = "00112233445566778899aabbccddeeff"
DEFAULT_KEY128    = "000102030405060708090a0b0c0d0e0f"
DEFAULT_KEY192    = "000102030405060708090a0b0c0d0e0f1011121314151617"
DEFAULT_KEY256    = ("000102030405060708090a0b0c0d0e0f"
                     "101112131415161718191a1b1c1d1e1f")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def validate_hex(value: str, name: str, expected_chars: int) -> str:
    """Normalise to lower-case and validate length / character set."""
    value = value.strip().lower()
    if len(value) != expected_chars:
        raise ValueError(
            f"{name} must be {expected_chars} hex chars "
            f"({expected_chars // 2} bytes), got {len(value)}"
        )
    invalid = set(value) - set("0123456789abcdef")
    if invalid:
        raise ValueError(f"{name} contains non-hex characters: {invalid}")
    return value


def build_packet(plaintext: str, key128: str,
                 key192: str, key256: str) -> bytes:
    """Concatenate the four fields into the 176-byte UART packet."""
    packet = plaintext + key128 + key192 + key256
    assert len(packet) == PACKET_LEN, f"Bug: packet is {len(packet)} chars"
    return packet.encode("ascii")


def auto_detect_port() -> str:
    """Return the first USB-serial port found, or raise RuntimeError."""
    ports = list(serial.tools.list_ports.comports())
    usb_ports = [p for p in ports
                 if "USB" in p.description.upper()
                 or "UART" in p.description.upper()
                 or "CP210" in p.description.upper()
                 or "FTDI"  in p.description.upper()]
    if usb_ports:
        return usb_ports[0].device
    if ports:
        return ports[0].device
    raise RuntimeError(
        "No serial port found.  Connect the Basys 3 USB cable and "
        "specify --port manually."
    )


def send_and_receive(port: str, packet: bytes) -> list:
    """
    Open *port*, send *packet*, collect the 6 reply lines, return them.
    Raises serial.SerialException or RuntimeError on failure.
    """
    with serial.Serial(port, BAUD_RATE,
                       bytesize=serial.EIGHTBITS,
                       parity=serial.PARITY_NONE,
                       stopbits=serial.STOPBITS_ONE,
                       timeout=REPLY_TIMEOUT) as ser:
        # Flush any stale data
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        print(f"[INFO] Port {port} opened at {BAUD_RATE} baud")
        print(f"[INFO] Sending {len(packet)}-byte packet to FPGA …")
        ser.write(packet)
        ser.flush()

        # Collect reply lines
        lines = []
        print("[INFO] Waiting for FPGA response …")
        for i in range(NUM_REPLY_LINES):
            raw = ser.readline()
            if not raw:
                raise RuntimeError(
                    f"Timeout waiting for response line {i + 1} "
                    f"of {NUM_REPLY_LINES}"
                )
            lines.append(raw.decode("ascii", errors="replace").strip())

        return lines


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        description="Send plaintext + AES keys to Basys 3 FPGA over UART "
                    "and display encryption / decryption results."
    )
    parser.add_argument("--port",
                        help="Serial port (e.g. COM3 or /dev/ttyUSB0). "
                             "Auto-detected when omitted.")
    parser.add_argument("--plaintext", default=DEFAULT_PLAINTEXT,
                        help=f"128-bit plaintext as 32 hex chars "
                             f"(default: {DEFAULT_PLAINTEXT})")
    parser.add_argument("--key128", default=DEFAULT_KEY128,
                        help=f"AES-128 key as 32 hex chars "
                             f"(default: {DEFAULT_KEY128})")
    parser.add_argument("--key192", default=DEFAULT_KEY192,
                        help=f"AES-192 key as 48 hex chars "
                             f"(default: {DEFAULT_KEY192})")
    parser.add_argument("--key256", default=DEFAULT_KEY256,
                        help=f"AES-256 key as 64 hex chars")
    return parser.parse_args()


def main():
    args = parse_args()

    # Validate / normalise
    try:
        plaintext = validate_hex(args.plaintext, "plaintext", 32)
        key128    = validate_hex(args.key128,    "key128",    32)
        key192    = validate_hex(args.key192,    "key192",    48)
        key256    = validate_hex(args.key256,    "key256",    64)
    except ValueError as exc:
        print(f"ERROR: {exc}")
        sys.exit(1)

    # Resolve port
    port = args.port
    if port is None:
        try:
            port = auto_detect_port()
            print(f"[INFO] Auto-detected serial port: {port}")
        except RuntimeError as exc:
            print(f"ERROR: {exc}")
            sys.exit(1)

    # Summary
    print()
    print("=" * 60)
    print("  AES-UART Host  –  Basys 3 FPGA")
    print("=" * 60)
    print(f"  Plaintext : {plaintext}")
    print(f"  AES-128 K : {key128}")
    print(f"  AES-192 K : {key192}")
    print(f"  AES-256 K : {key256}")
    print("=" * 60)
    print()

    # Build packet and communicate
    packet = build_packet(plaintext, key128, key192, key256)
    try:
        lines = send_and_receive(port, packet)
    except (serial.SerialException, RuntimeError) as exc:
        print(f"ERROR: {exc}")
        sys.exit(1)

    # Display results
    print()
    print("=" * 60)
    print("  FPGA Response")
    print("=" * 60)
    for line in lines:
        print(f"  {line}")
    print("=" * 60)
    print()

    # Optional: verify round-trip (decrypted == original plaintext)
    expected_dec = plaintext
    all_ok = True
    for line in lines:
        if "_DEC:" in line:
            label, _, result = line.partition(":")
            if result.strip().lower() != expected_dec:
                print(f"WARNING: {label} mismatch – "
                      f"got {result.strip()}, expected {expected_dec}")
                all_ok = False
    if all_ok:
        print("[PASS] All decrypted outputs match the original plaintext.")


if __name__ == "__main__":
    main()
