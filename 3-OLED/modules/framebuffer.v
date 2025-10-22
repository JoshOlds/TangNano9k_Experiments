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
integer i;

// Local read registers
reg [7:0] r_left_byte = 0;
reg [7:0] r_right_byte = 0;

// Local write registers
reg [7:0] w_left_byte = 0;
reg [7:0] w_right_byte = 0;
reg [7:0] w_left_mask = 0;
reg [7:0] w_right_mask = 0;
reg [7:0] w_masked_left = 0;
reg [7:0] w_masked_right = 0;

// Column Read Registers
reg [7:0] col_read_b0 = 0;
reg [7:0] col_read_b1 = 0;
reg [7:0] col_read_b2 = 0;
reg [7:0] col_read_b3 = 0;
reg [7:0] col_read_b4 = 0;
reg [7:0] col_read_b5 = 0;
reg [7:0] col_read_b6 = 0;
reg [7:0] col_read_b7 = 0;

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
        r_left_byte <= 8'h00;
        r_right_byte <= 8'h00;
        w_left_byte <= 8'h00;
        w_right_byte <= 8'h00;
        w_left_mask <= 8'h00;
        w_right_mask <= 8'h00;
        w_masked_left <= 8'h00;
        w_masked_right <= 8'h00;
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
                r_left_byte = framebuffer[(r_ypos * (H_PIXELS / 8)) + (r_xpos / 8)] << (r_xpos % 8);
                r_right_byte = framebuffer[(r_ypos * (H_PIXELS / 8)) + (r_xpos / 8) + 1] >> (8 - (r_xpos % 8));
                dout <= (r_left_byte | r_right_byte);
            end
        end else begin
            //Column read mode
            dout <= {
                framebuffer[(r_ypos * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 1) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 2) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 3) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 4) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 5) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 6) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8)],
                framebuffer[((r_ypos + 7) * (H_PIXELS / 8)) + (r_xpos / 8)][7 - (r_xpos % 8)]
            };

            col_read_b0 <= (framebuffer[(r_ypos * (H_PIXELS / 8)) + (r_xpos / 8)] << (7 - (r_xpos % 8)));
            col_read_b1 <= framebuffer[((r_ypos + 1) * (H_PIXELS / 8)) + (r_xpos / 8)];
            col_read_b2 <= framebuffer[((r_ypos + 2) * (H_PIXELS / 8)) + (r_xpos / 8)];
            col_read_b3 <= framebuffer[((r_ypos + 3) * (H_PIXELS / 8)) + (r_xpos / 8)];
            col_read_b4 <= framebuffer[((r_ypos + 4) * (H_PIXELS / 8)) + (r_xpos / 8)];
            col_read_b5 <= framebuffer[((r_ypos + 5) * (H_PIXELS / 8)) + (r_xpos / 8)];
            col_read_b6 <= framebuffer[((r_ypos + 6) * (H_PIXELS / 8)) + (r_xpos / 8)];
            col_read_b7 <= framebuffer[((r_ypos + 7) * (H_PIXELS / 8)) + (r_xpos / 8)];
            //dout <= 8'hFF;
        end
    end

    // Write Operation
    if (we && !rst) begin
        if(w_xpos % 8 == 0) begin
            // Aligned write
            framebuffer[(w_ypos * (H_PIXELS / 8)) + (w_xpos / 8)] <= din;
        end else begin
            // Unaligned write - split into two bytes
            // Create masks to preserve existing bits that we don't want to write over
            w_left_mask = 8'hFF << (w_xpos % 8);
            w_right_mask = ~(8'hFF << (w_xpos % 8));

            // Mask the existing bytes in the framebuffer
            w_masked_left = (framebuffer[(w_ypos * (H_PIXELS / 8)) + (w_xpos / 8)] & w_left_mask);
            w_masked_right = (framebuffer[(w_ypos * (H_PIXELS / 8)) + (w_xpos / 8) + 1] & w_right_mask);

            // Split the input data into two parts and shift to correct positions
            w_left_byte = din >> (w_xpos % 8);
            w_right_byte = din << (8 - (w_xpos % 8));

            // Write the combined masked and new data back to the framebuffer
            framebuffer[(w_ypos * (H_PIXELS / 8)) + (w_xpos / 8)] <= w_masked_left | w_left_byte;
            framebuffer[(w_ypos * (H_PIXELS / 8)) + (w_xpos / 8) + 1] <= w_masked_right | w_right_byte;
        end
    end

end

endmodule