

`default_nettype none
module oled_top(
    input clk_pin, // FPGA clock input (assumes TangNano9k 27Mhz clock)
    input btn1_pin, // FPGA Button 1
    output reg oled_d0_pin, // OLED d0 pin (acts as SCLK for SPI)
    output reg oled_d1_pin, // OLED d1 pin (acts as SDIN for SPI) - data is shifted in on rising edge of SCLK, and is MSB first
    output reg oled_res_pin, // OLED reset pin
    output reg oled_dc_pin, // OLED command pin - Command == LOW, pixel data == HIGH
    output reg oled_cs_pin, // OLED chip select pin - pull low to communicate with module
    output [5:0] led_pin
);

// Button signals
reg button1_active_high = 0;
assign button1_active_high = ~btn1_pin; // Invert button signal to be active high

// Framebuffer drive registers /////////////////////////////////////////
wire fb_busy; // Framebuffer busy signal
reg fb_we = 0; // Framebuffer write enable
reg [7:0] fb_w_xpos = 0; // Framebuffer write x position
reg [7:0] fb_w_ypos = 0; // Framebuffer write y position
reg [7:0] fb_din = 0; // Framebuffer data input (8 pixels, 1 bit each)  
wire fb_w_data_valid; // Framebuffer write data valid signal

wire fb_re; // Framebuffer read enable
wire [7:0] fb_dout; // Framebuffer data output (8 pixels, 1 bit each)
wire [7:0] fb_r_xpos; // Framebuffer read x position
wire [7:0] fb_r_ypos; // Framebuffer read y position
wire fb_r_mode; // Framebuffer read mode (0: horizontal read, 1: column read)
wire fb_r_data_valid; // Framebuffer read data valid signal
wire fb_rst_complete; // Framebuffer reset complete flag

framebuffer_monochrome fb(
    .clk(clk_pin),
    .rst(button1_active_high),
    .rst_complete(fb_rst_complete),
    .busy(fb_busy),
    .we(fb_we),
    .w_data_valid(fb_w_data_valid),
    .w_xpos(fb_w_xpos),
    .w_ypos(fb_w_ypos),
    .din(fb_din),
    .re(fb_re),
    .r_data_valid(fb_r_data_valid),
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
    .led_pin_o(led_pin[3:0]),
    .fb_dout(fb_dout),
    .fb_data_valid(fb_r_data_valid),
    .fb_busy(fb_busy),
    .fb_r_xpos(fb_r_xpos),
    .fb_r_ypos(fb_r_ypos),
    .fb_r_mode(fb_r_mode),
    .fb_re(fb_re)
);

// Framebuffer test registers
reg [31:0] write_counter = 0; // Counter for 1 second delay (27Mhz clock)
reg [7:0] write_x = 0; // Current write X position
reg [7:0] write_y = 0; // Current write Y position
reg write_in_progress = 1;

assign led_pin[5] = ~write_in_progress; // Indicate when a write is in progress
assign led_pin[4] = fb_busy; // Indicate when framebuffer is busy

// Simple test pattern writer 
reg [7:0] write_phase = 0;
reg rollover_invert = 1'b0;
always @(posedge clk_pin) begin
    // Reset test counters on button press
    if(button1_active_high) begin
        write_counter <= 0;
        write_x <= 0;
        write_y <= 0;
        write_in_progress <= 1;
        write_phase <= 0;
        fb_we <= 0;
    end 

    if (!write_in_progress) begin
        write_counter <= write_counter + 1;
        if(write_counter >= 27000) begin // 1 second at 27Mhz
            write_counter <= 0;
            write_in_progress <= 1;
            // Increment position
            if(write_x >= 127) begin 
                write_x <= 0;
                if(write_y >= 63) begin
                    write_y <= 0;
                    rollover_invert <= ~rollover_invert;
                end else begin
                    write_y <= write_y + 1;
                end
            end else begin
                write_x <= write_x + 16;
            end
        end
    end

    if(write_in_progress) begin
        case (write_phase)
            0: begin
                if (!fb_busy) begin
                    fb_w_xpos <= write_x;
                    fb_w_ypos <= write_y;
                    fb_we <= 1;// Wait one cycle for xpos and ypos to propagate
                    if(rollover_invert) begin
                        fb_din <= 8'h00;
                    end else begin
                        fb_din <= 8'hFF;
                    end
                    write_phase <= 1;
                end
            end
            1: begin
                if (fb_w_data_valid) begin
                    fb_we <= 0;
                    write_in_progress <= 0;
                    write_phase <= 0;
                end   
            end
            default: begin
                write_phase <= 0;
            end
        endcase
    end else begin
        fb_we <= 0;
        write_phase <= 0;
    end     
end
endmodule