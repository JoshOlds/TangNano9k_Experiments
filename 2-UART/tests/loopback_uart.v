// https://learn.lushaylabs.com/tang-nano-9k-debugging/

// Module to loopback received UART data and display status on LEDs

module loopback_uart(
    input clk_pin_i,
    input uart_rx_pin_i,
    output uart_tx_pin_o,
    output [5:0] led_pins_o
);

    // UART signals
    wire [7:0] uart_rx_data;
    reg [7:0] uart_tx_data;
    wire uart_rx_byte_ready;
    wire uart_tx_ready;
    reg uart_tx_trigger;
    wire [3:0] debug_state;

    assign led_pins_o[5] = uart_rx_pin_i; // Show RX line state on LED 5

    uart uart1(
        .clk_i(clk_pin_i),
        .uart_rx_i(uart_rx_pin_i),
        .rx_byte_ready_o(uart_rx_byte_ready),
        .rx_data_o(uart_rx_data),
        .uart_tx_o(uart_tx_pin_o),
        .tx_data_i(uart_tx_data),
        .tx_trigger_i(uart_tx_trigger),
        .tx_complete_o(uart_tx_ready),
        .rx_state_debug(debug_state)
    );

    // Loopback UART for testing
    reg tx_loopback_sent_already = 0; // To avoid multiple triggers for the same byte in loopback mode
    always @(posedge clk_pin_i) begin
        uart_tx_trigger <= 0; // Default to no trigger
        if(!tx_loopback_sent_already && uart_rx_byte_ready && uart_tx_ready) begin
            uart_tx_data <= uart_rx_data; // Load the data to be sent with the last received byte
            tx_loopback_sent_already <= 1;
            uart_tx_trigger <= 1; // Trigger the TX to send the byte
        end
        if(!uart_rx_byte_ready) begin
            tx_loopback_sent_already <= 0;
        end
    end

endmodule