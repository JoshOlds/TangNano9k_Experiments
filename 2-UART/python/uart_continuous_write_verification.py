# Continuous UART Write Verification Script
# This script continuously reads from a UART interface and verifies
# that the incoming data matches a predefined repeating pattern.

import serial
import sys
import time

# Configuration
SERIAL_PORT = 'COM6'      # Change to your serial port
BAUD_RATE = 1000000      # Set to your FPGA UART baud rate
EXPECTED_PATTERN = b'AC'  # Repeating pattern to check (change as needed)
READ_TIMEOUT = 1          # Seconds

def main():
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=READ_TIMEOUT)
        ser.flush()
        print(f"Opened {SERIAL_PORT} at {BAUD_RATE} baud.")
    except serial.SerialException as e:
        print(f"Error opening serial port: {e}")
        sys.exit(1)

    total_bytes = 0
    error_bytes = 0
    pattern_len = len(EXPECTED_PATTERN)
    pattern_offset = 0  # where we are in the repeating pattern

    try:
        while True:
            data = ser.read(1024)
            if not data:
                print("No data received. Waiting...")
                time.sleep(0.1)
                continue

            base_index = total_bytes
            chunk_errors = []
            for i, b in enumerate(data):
                expected = EXPECTED_PATTERN[pattern_offset]
                if b != expected:
                    chunk_errors.append(base_index + i)
                    error_bytes += 1
                # advance pattern offset per-byte
                pattern_offset = (pattern_offset + 1) % pattern_len

            total_bytes += len(data)

            if chunk_errors:
                # print a concise summary of mismatches (positions)
                print(f"Mismatches at positions (abs): {chunk_errors}")
                # Optionally show the raw received chunk for debugging
                print(f"Received bytes: {data}")

            print(f"Total bytes: {total_bytes}, Errors: {error_bytes}", end='\r')
    except KeyboardInterrupt:
        print("\nStopped by user.")
    finally:
        ser.close()

if __name__ == "__main__":
    main()