// https://learn.lushaylabs.com/tang-nano-9k-debugging/

// Top module to instantiate different UART test modules
// Uncomment the desired module to test

`default_nettype none

module uart_top(
    input clk_pin,
    input uart_rx_pin,
    output uart_tx_pin,
    output [5:0] led_pins
);

    // Set the LEDs to on (active low)
    //assign led_pins = 6'b000000;

    loopback_uart lb1(
        .clk_pin_i(clk_pin),
        .uart_rx_pin_i(uart_rx_pin),
        .uart_tx_pin_o(uart_tx_pin),
        .led_pins_o(led_pins)
    );

    // uart_write_test uart1(
    //     .clk_pin_i(clk_pin),
    //     .uart_rx_pin_i(uart_rx_pin),
    //     .uart_tx_pin_o(uart_tx_pin),
    //     .led_pins_o(led_pins)
    // );

    // led_uart led_uart1(
    //     .clk_pin_i(clk_pin),
    //     .uart_rx_pin_i(uart_rx_pin),
    //     .uart_tx_pin_o(uart_tx_pin),
    //     .led_pins_o(led_pins)
    // );

endmodule