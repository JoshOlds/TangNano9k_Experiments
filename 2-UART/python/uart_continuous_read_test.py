import serial
import time
import random
import argparse
import sys
import shutil

def uart_continuous_read_test(port, baudrate, bytes_per_send, send_interval, total_sends):
    ser = serial.Serial(port, baudrate, timeout=1)
    print(f"Opened serial port {port} at {baudrate} baud.")

    def _draw_progress(bytes_sent, total_bytes):
        # single-line progress bar, updates in-place
        if total_bytes <= 0:
            percent = 1.0
        else:
            percent = min(max(bytes_sent / total_bytes, 0.0), 1.0)
        term_width = shutil.get_terminal_size(fallback=(80, 20)).columns
        # reserve space for " [bar] 100.0% 123/456 bytes"
        reserved = 32
        bar_len = max(10, term_width - reserved)
        bar_len = min(bar_len, 60)
        filled = int(round(bar_len * percent))
        bar = "=" * filled + ">" + "." * max(0, bar_len - filled - 1) if filled < bar_len else "=" * bar_len
        percent_text = f"{percent*100:6.2f}%"
        count_text = f"{bytes_sent}/{total_bytes} bytes"
        sys.stdout.write(f"\r[{bar}] {percent_text} {count_text}")
        sys.stdout.flush()

    total_bytes = bytes_per_send * total_sends
    bytes_sent = 0

    try:
        for i in range(total_sends):
            # Generate random bytes
            tx_bytes = bytes(random.getrandbits(8) for _ in range(bytes_per_send))
            ser.write(tx_bytes)
            bytes_sent += len(tx_bytes)
            _draw_progress(bytes_sent, total_bytes)
            time.sleep(send_interval)
    finally:
        ser.close()
        # ensure we move to the next line after progress bar
        print()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="UART loopback test script")
    parser.add_argument("--port", required=True, help="Serial port (e.g. COM3 or /dev/ttyUSB0)")
    parser.add_argument("--baudrate", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--bytes", type=int, default=8, help="Bytes per send (default: 8)")
    parser.add_argument("--interval", type=float, default=0.1, help="Interval between sends in seconds (default: 0.1)")
    parser.add_argument("--count", type=int, default=100, help="Total number of sends (default: 100)")
    args = parser.parse_args()

    uart_continuous_read_test(args.port, args.baudrate, args.bytes, args.interval, args.count)