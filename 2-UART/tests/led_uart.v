// Simple top-level module to connect UART to LEDs
// Displays the last received byte on the LEDs (inverted for active-low LEDs)

module led_uart(
    input clk_pin,
    input uart_rx_pin,
    output uart_tx_pin,
    output [5:0] led_pins
);

    // UART signals
    wire [7:0] uart_rx_data;
    reg [7:0] uart_tx_data;
    wire uart_rx_byte_ready;
    wire uart_tx_ready;
    reg uart_tx_trigger;
    wire [3:0] debug_state;

    reg [7:0] latched_uart_rx_data = 0;

    uart uart1(
        .clk_i(clk_pin),
        .uart_rx_i(uart_rx_pin),
        .rx_byte_ready_o(uart_rx_byte_ready),
        .rx_data_o(uart_rx_data),
        .uart_tx_o(uart_tx_pin),
        .tx_data_i(uart_tx_data),
        .tx_trigger_i(uart_tx_trigger),
        .tx_complete_o(uart_tx_ready),
        .rx_state_debug(debug_state)
    );

    // Latch the last received byte for display on LEDs
    always @(posedge clk_pin) begin
        if (uart_rx_byte_ready) begin
            latched_uart_rx_data <= uart_rx_data;
        end
    end

    //Drive LEDs from UART
    always @(posedge clk_pin) begin
        led_pins[5:0] <= ~latched_uart_rx_data[5:0];
    end

endmodule