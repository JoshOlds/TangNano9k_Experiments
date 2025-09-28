# Simple UART Static Read Test Script
# This script continuously sends a fixed byte (0xAA) over UART.

import serial
import threading
import time
import sys

def main():

    port = "COM6"
    baudrate = 1000000
    byte_to_send = 0xAA
    if not (0 <= byte_to_send <= 255):
        print("Invalid byte value.")
        sys.exit(1)

    ser = serial.Serial(port, baudrate, timeout=0)
    ser.flush()
    running = True

    def send_bytes():
        while running:
            ser.write(bytes([byte_to_send]))
            #time.sleep(0.01)  # send every 10ms

    sender_thread = threading.Thread(target=send_bytes)
    sender_thread.daemon = True
    sender_thread.start()

    print("Press Enter to stop sending...")
    input()
    running = False
    sender_thread.join()
    ser.close()
    print("Stopped.")

if __name__ == "__main__":
    main()