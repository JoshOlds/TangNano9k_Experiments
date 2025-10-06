`default_nettype none

module oled_top(
    input clk_pin, // FPGA clock input (assumes TangNano9k 27Mhz clock)
    output reg oled_d0_pin, // OLED d0 pin (acts as SCLK for SPI)
    output reg oled_d1_pin, // OLED d1 pin (acts as SDIN for SPI) - data is shifted in on rising edge of SCLK, and is MSB first
    output reg oled_res_pin, // OLED reset pin
    output reg oled_dc_pin, // OLED command pin - Command == LOW, pixel data == HIGH
    output reg oled_cs_pin // OLED chip select pin - pull low to communicate with module
);

ssd1780_driver oled_driver(
    .clk(clk_pin),
    .sclk(oled_d0_pin),
    .sdin(oled_d1_pin), 
    .res(oled_res_pin), 
    .cmd(oled_dc_pin), 
    .cs(oled_cs_pin) 
);

endmodule