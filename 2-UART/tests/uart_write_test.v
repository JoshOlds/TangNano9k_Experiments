    module uart_write_test(
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
    
    //Send alternating 0xAA and 0x55 as fast as possible (debounced so we only send once per uart_tx_ready pulse)
    reg [0:1] counter = 0;
    reg tx_ready_seen = 0;
    always @(posedge clk_pin) begin
        uart_tx_trigger <= 0; // Default to no trigger
        if (uart_tx_ready) begin
            if (!tx_ready_seen) begin
                tx_ready_seen <= 1; // mark that we've handled this ready pulse
                if (counter == 0) begin
                    counter <= counter + 1;
                    uart_tx_data <= "A";
                end else begin
                    counter <= 0;
                    uart_tx_data <= "C";
                end
                uart_tx_trigger <= 1; // Trigger the TX to send the byte (only once per ready period)
            end
        end else begin
            // Ready is low: allow the next ready assertion to trigger another send
            tx_ready_seen <= 0;
        end
    end

endmodule