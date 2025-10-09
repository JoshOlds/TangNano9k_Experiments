`default_nettype none

module oled_top(
    input clk_pin, // FPGA clock input (assumes TangNano9k 27Mhz clock)
    input btn1_pin, // FPGA Button 1
    output reg oled_d0_pin, // OLED d0 pin (acts as SCLK for SPI)
    output reg oled_d1_pin, // OLED d1 pin (acts as SDIN for SPI) - data is shifted in on rising edge of SCLK, and is MSB first
    output reg oled_res_pin, // OLED reset pin
    output reg oled_dc_pin, // OLED command pin - Command == LOW, pixel data == HIGH
    output reg oled_cs_pin, // OLED chip select pin - pull low to communicate with module
    output [4:0] led_pin
);

reg button1_active_high = 0;
assign button1_active_high = ~btn1_pin; // Invert button signal to be active high

reg [15:0] clock_divider = 0;
reg oled_clk = 0;
always @(posedge clk_pin) begin
    clock_divider <= clock_divider + 1;
    oled_clk <= clock_divider[15]; // 411hz
end

ssd1309_driver oled_driver(
    .clk(clk_pin),
    .reset(button1_active_high),
    .sclk(oled_d0_pin),
    .sdin(oled_d1_pin), 
    .res(oled_res_pin), 
    .cmd(oled_dc_pin), 
    .cs(oled_cs_pin), 
    .led_pin_o(led_pin)
);

endmodule