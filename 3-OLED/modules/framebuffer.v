`default_nettype none

module framebuffer_monochrome
(
    input wire clk, // Module clock input
    input wire rst, // Module reset input (active high)
    input wire we, // Write enable input (active high)
    input wire re, // Read enable input (active high)
    input wire [7:0] xpos, // X position input for read or write (in pixels)
    input wire [7:0] ypos, // Y position input for read or write (in pixels)
    input wire [7:0] din, // Data input for write mode (8 pixels, 1 bit each)
    output reg [7:0] dout, // Data output for read mode (8 pixels, 1 bit each)
);

localparam H_PIXELS = 128; // Horizontal resolution in pixels
localparam V_PIXELS = 64; // Vertical resolution in pixels

reg [7:0] framebuffer [(H_PIXELS/8)*V_PIXELS-1:0]; // Framebuffer memory (1 bit per pixel, 8 pixels per byte)

// Function to write 0s to the framebuffer
function clear_framebuffer
integer i;
for(i = 0; i < (H_PIXELS/8)*V_PIXELS; i = i + 1) begin
    framebuffer[i] = 8'h00;
end


always @(posedge clk) begin
    if(rst) begin
        dout
    end


end

endmodule