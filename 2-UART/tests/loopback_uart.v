// https://learn.lushaylabs.com/tang-nano-9k-debugging/

// Module to loopback received UART data and display status on LEDs

module loopback_uart(
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

    // Loopback UART for testing
    reg tx_loopback_sent_already = 0; // To avoid multiple triggers for the same byte in loopback mode
    always @(posedge clk_pin) begin
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

    //Drive LEDs from UART
    always @(posedge clk_pin) begin
        led_pins[3:0] <= ~debug_state[3:0];
        led_pins[4] <= ~uart_rx_byte_ready;
        led_pins[5] <= uart_rx_pin;
    end

endmodule