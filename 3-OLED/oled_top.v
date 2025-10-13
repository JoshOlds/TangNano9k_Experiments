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

// Framebuffer drive registers
reg fb_we = 0; // Framebuffer write enable
reg [7:0] fb_w_xpos = 0; // Framebuffer write x position
reg [7:0] fb_w_ypos = 0; // Framebuffer write y position
reg [7:0] fb_din = 0; // Framebuffer data input (8 pixels, 1 bit each)  
reg fb_re = 0; // Framebuffer read enable
wire [7:0] fb_dout; // Framebuffer data output (8 pixels, 1 bit each)
reg [7:0] fb_r_xpos = 0; // Framebuffer read x position
reg [7:0] fb_r_ypos = 0; // Framebuffer read y position
reg fb_r_mode = 0; // Framebuffer read mode (0: horizontal read, 1: column read)

framebuffer_monochrome fb(
    .clk(clk_pin),
    .rst(button1_active_high),
    .we(fb_we),
    .w_xpos(fb_w_xpos),
    .w_ypos(fb_w_ypos),
    .din(fb_din),
    .re(fb_re),
    .dout(fb_dout),
    .r_xpos(fb_r_xpos),
    .r_ypos(fb_r_ypos),
    .r_mode(fb_r_mode)
);

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