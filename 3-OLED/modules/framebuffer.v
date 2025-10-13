`default_nettype none

module framebuffer_monochrome
(
    input wire clk, // Module clock input
    input wire rst, // Module reset input (active high)

    input wire we, // Write enable input (active high)
    input wire [7:0] w_xpos, // X position input for write (in pixels)
    input wire [7:0] w_ypos, // Y position input for write (in pixels)
    input wire [7:0] din, // Data input for write mode (8 pixels, 1 bit each)

    input wire re, // Read enable input (active high)
    output reg [7:0] dout, // Data output for read mode (8 pixels, 1 bit each)
    input wire [7:0] r_xpos, // X position input for read (in pixels)
    input wire [7:0] r_ypos, // Y position input for read (in pixels)
    input wire r_mode // Read mode input (0: horizontal read, 1: column read)
);

localparam H_PIXELS = 128; // Horizontal resolution in pixels
localparam V_PIXELS = 64; // Vertical resolution in pixels

reg [7:0] framebuffer [(H_PIXELS/8)*V_PIXELS-1:0]; // Framebuffer memory (1 bit per pixel, 8 pixels per byte)
integer i = 0;

// Local read registers
reg [7:0] r_left_byte;
reg [7:0] r_right_byte;

// Local write registers
reg [7:0] w_left_byte;
reg [7:0] w_right_byte;

// Function to write 0s to the framebuffer
task clear_framebuffer;
begin
    for(i = 0; i < (H_PIXELS/8)*V_PIXELS; i = i + 1) begin
        framebuffer[i] <= 8'h00;
    end
end
endtask

// Initialize outputs
initial begin
    clear_framebuffer;
    dout <= 8'h00;
end


always @(posedge clk) begin
    // Clear framebuffer and outputs on reset
    if(rst) begin
        clear_framebuffer;
        dout <= 8'h00;
    end

    // Read Operation
    if (re && !rst) begin
        if (r_mode == 1'b0) begin
            // Horizontal read mode
            if(r_xpos % 8 == 0) begin
                // Aligned read
                dout <= framebuffer[(r_ypos * (H_PIXELS / 8)) + (r_xpos / 8)];
            end else begin
                // Unaligned read - assemble from two bytes
                r_left_byte = framebuffer[(r_ypos * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8) : 0];
                r_right_byte = framebuffer[(r_ypos * (H_PIXELS / 8)) + (r_xpos / 8) + 1][7 : 8 - (r_xpos % 8)];
                dout <= {r_left_byte, r_right_byte};
            end
        end else begin
            // Column read mode
            dout <= {
                framebuffer[(r_ypos * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8): 7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 1) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8): 7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 2) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8): 7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 3) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8): 7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 4) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8): 7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 5) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8): 7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 6) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8): 7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 7) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8): 7 - (r_xpos % 8)]
            };
        end
    end

    // Write Operation
    if (we && !rst) begin
        if(w_xpos % 8 == 0) begin
            // Aligned write
            framebuffer[(w_ypos * (H_PIXELS / 8)) + (w_xpos / 8)] <= din;
        end else begin
            // Unaligned write - split into two bytes
            w_left_byte = framebuffer[(w_ypos * (H_PIXELS / 8)) + (w_xpos / 8)];
            w_right_byte = framebuffer[(w_ypos * (H_PIXELS / 8)) + (w_xpos / 8) + 1];

            w_left_byte[7 - (w_xpos % 8) : 0] <= din[7 : (w_xpos % 8)];
            w_right_byte[7 : 8 - (w_xpos % 8)] <= din[(w_xpos % 8) - 1 : 0];

            framebuffer[(w_ypos * (H_PIXELS / 8)) + (w_xpos / 8)] <= w_left_byte;
            framebuffer[(w_ypos * (H_PIXELS / 8)) + (w_xpos / 8) + 1] <= w_right_byte;
        end
    end

end

endmodule