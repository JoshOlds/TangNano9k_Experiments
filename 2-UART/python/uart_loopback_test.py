# UART Loopback Test Script
# This script sends random byte sequences to a UART interface and verifies
# that the received data matches the sent data, indicating a successful loopback.

import serial
import time
import random
import argparse
import sys
import shutil

def uart_loopback_test(port, baudrate, bytes_per_send, send_interval, total_sends):
    ser = serial.Serial(port, baudrate, stopbits=2, timeout=1)
    ser.flush()
    print(f"Opened serial port {port} at {baudrate} baud.")

    success = 0
    fail = 0

    total_bytes = bytes_per_send * total_sends
    bytes_sent = 0

    def _draw_progress(bytes_sent, total_bytes):
        if total_bytes <= 0:
            percent = 1.0
        else:
            percent = min(max(bytes_sent / total_bytes, 0.0), 1.0)
        term_width = shutil.get_terminal_size(fallback=(80, 20)).columns
        reserved = 45  # Increased to accommodate pass/fail counts
        bar_len = max(10, term_width - reserved)
        bar_len = min(bar_len, 60)
        filled = int(round(bar_len * percent))
        bar = "=" * filled + ">" + "." * max(0, bar_len - filled - 1) if filled < bar_len else "=" * bar_len
        percent_text = f"{percent*100:6.2f}%"
        count_text = f"{bytes_sent}/{total_bytes}B"
        status_text = f"[Pass:{success} Fail:{fail}]"
        sys.stdout.write(f"\r[{bar}] {percent_text} {count_text} {status_text}")
        sys.stdout.flush()

    try:
        for i in range(total_sends):
            # Generate random bytes
            tx_bytes = bytes(random.getrandbits(8) for _ in range(bytes_per_send))
            ser.write(tx_bytes)
            time.sleep(send_interval)

            rx_bytes = ser.read(bytes_per_send)
            if rx_bytes == tx_bytes:
                success += 1
                bytes_sent += len(tx_bytes)
            else:
                print(f"\n[{i+1}/{total_sends}] FAIL: Sent {tx_bytes.hex()}, Received {rx_bytes.hex()}")
                fail += 1
                bytes_sent += len(tx_bytes)  # Still count the bytes even on failure
            _draw_progress(bytes_sent, total_bytes)
    finally:
        ser.close()
        # ensure we move to the next line after progress bar
        print()
        print(f"Test complete. Success: {success}, Fail: {fail}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="UART loopback test script")
    parser.add_argument("--port", required=True, help="Serial port (e.g. COM3 or /dev/ttyUSB0)")
    parser.add_argument("--baudrate", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--bytes", type=int, default=8, help="Bytes per send (default: 8)")
    parser.add_argument("--interval", type=float, default=0.1, help="Interval between sends in seconds (default: 0.1)")
    parser.add_argument("--count", type=int, default=100, help="Total number of sends (default: 100)")
    args = parser.parse_args()

    uart_loopback_test(args.port, args.baudrate, args.bytes, args.interval, args.count)