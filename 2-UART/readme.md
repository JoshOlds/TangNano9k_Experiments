# UART for TangNano9k (Verilog)

This folder provides a Verilog implementation of a simple UART designed for
experimentation on the TangNano9k FPGA (see https://lushaylabs.com and
the project documentation). 

The core UART is in `modules/uart/uart.v` and is
configured to work with a 27 MHz system clock and a default DELAY_FRAMES that
targets a 1M baud rate (see the module parameter for details). 

A set
of lightweight test modules and Python test scripts are included to exercise
and verify the UART using a USB-to-serial connection.


## Verilog sources / modules

- `modules/uart/uart.v`
	- The UART transmit/receive module. It implements RX and TX state machines
		and exposes signals such as `rx_byte_ready_o`, `rx_data_o`, `tx_complete_o`
		and `uart_tx_o`. The module is parameterized by `DELAY_FRAMES` (baud
		timing) and contains RX sampling at the mid-bit point and an LSB-first
		8-bit data format.

- `top.v`
	- Top-level wrapper that instantiates one of the test/example modules. 
    - Adjust this file to execute tests as needed. 

### Test modules (examples)

- `tests/uart_write_test.v`
	- Simple test module that writes alternating characters (comments indicate
		alternating `"A"` (0x41) and `"C"` (0x43)) as fast as the UART can send
		them. Uses the `uart` module and its `tx_complete_o` / `tx_trigger_i`
		handshake to pace writes.

- `tests/loopback_uart.v`
	- Loopback module: receives bytes on RX and immediately retransmits them
		on TX (when the transmitter is ready). Also drives LEDs and provides a
		`rx_state_debug` signal for basic visual debug.

- `tests/led_uart.v`
	- Simple example that latches the last received UART byte and displays the
		lower 6 bits on LEDs (inverted for active-low LED connections).

### Testbench

- `testbenches/uart_tb.v`
	- A small Verilog testbench that instantiates the `uart` module and
		exercises receive and transmit paths. It includes simple stimulus and
		dumps a `uart.vcd` trace for waveform inspection.

### Python helper and test scripts

- `python/uart_static_read_test.py`
	- A tiny script that continuously sends a fixed byte (0xAA) to the serial
		port. Useful for basic signal checks and receiver testing.

- `python/uart_loopback_test.py`
	- Sends random byte sequences to a serial port and verifies that the bytes
		received match what was sent (useful when the FPGA is running a
		loopback module). Prints progress and a pass/fail summary.

- `python/uart_continuous_write_verification.py`
	- Continuously reads from the UART and verifies the incoming data against
		a predefined repeating pattern (default `b"AC"`). Reports mismatch
		positions and a running error count — handy for long-running
		integrity checks.

- `python/uart_continuous_read_test.py`
	- A simple script that sends blocks of random bytes continuously to the
		UART, with a progress indicator. (Name suggests "read" but the script
		implements continuous writes for verification.)

## Quick usage notes

- Python scripts require the `pyserial` package. Install with:

```powershell
pip install pyserial
```

- Example: run the loopback verifier (replace `COM6` with your port):

```powershell
python .\python\uart_loopback_test.py --port COM6 --baudrate 1000000 --bytes 8 --interval 0.01 --count 1000
```

- Example: start the static sender to flood the UART with 0xAA on `COM6`:

```powershell
python .\python\uart_static_read_test.py
```

## Notes and assumptions

- The `uart` Verilog module assumes a system clock of 27 MHz in the provided
	configuration.
- The Python scripts in `python/` default to `COM6` and 1,000,000 baud in the
	current code; update those values or pass CLI arguments where available.


