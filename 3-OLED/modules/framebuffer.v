
//TODO: Can prevent out of bounds writes by clamping w_xpos and w_ypos in an always block!
// TODO: need to not write while reading, because unaligned writes use the read port to read existing data first
`default_nettype none

module framebuffer_monochrome
(
    input wire clk, // Module clock input
    input wire rst, // Module reset input (active high)

    input wire we, // Write enable input (active high)
    output reg w_data_valid = 0, // Write data valid output (indicates din is accepted)
    input wire [7:0] w_xpos, // X position input for write (in pixels)
    input wire [7:0] w_ypos, // Y position input for write (in pixels)
    input wire [7:0] din, // Data input for write mode (8 pixels, 1 bit each)

    input wire re, // Read enable input (active high)
    output reg r_data_valid = 0, // Read data valid output (indicates dout is valid)
    output reg [7:0] dout, // Data output for read mode (8 pixels, 1 bit each)
    input wire [7:0] r_xpos, // X position input for read (in pixels)
    input wire [7:0] r_ypos, // Y position input for read (in pixels)
    input wire r_mode // Read mode input (0: horizontal read, 1: column read)
);

// Initialize outputs
initial begin
    dout <= 8'h00;
    r_data_valid <= 0;
    w_data_valid <= 0;
end

localparam H_PIXELS = 128; // Horizontal resolution in pixels
localparam V_PIXELS = 64; // Vertical resolution in pixels

// Registers for dual port BRAM interface
reg [11:0] ram_r_addr = 0; // Read address (12 bits to cover 1024 bytes)
reg [11:0] ram_w_addr = 0; // Write address (12 bits to cover 1024 bytes)
reg [7:0] ram_din = 0; // Data input to BRAM
wire [7:0] ram_dout; // Data output from BRAM
reg ram_we; // Write enable to BRAM

// Dual Port BRAM Instance used for Framebuffer Storage
dual_port_bram #(
    .ADDR_WIDTH(12), // 128*64/8 = 1024 bytes = 2^10, so 12 bits is enough
    .DATA_WIDTH(8),
    .DEPTH((H_PIXELS/8)*V_PIXELS) // Total framebuffer size in bytes
) bram (
    .clk(clk),

    // Port A - Write Port
    .we_a(ram_we),
    .addr_a(w_addr),
    .din_a(ram_din),
    .dout_a(), // Unused

    // Port B - Read Port
    .we_b(1'b0), // Read only
    .addr_b(r_addr),
    .din_b(8'h00), // Unused
    .dout_b(ram_dout)
);


// Address calculation registers
reg [11:0] r_addr = 0;
reg [11:0] w_addr = 0;

// Local read registers
reg r_aligned_pipeline_flag = 0; // Pipeline flag for aligned read
reg [7:0] r_unaligned_pipeline_counter = 0; // Pipeline counter for unaligned read
reg [7:0] r_column_pipeline_counter = 0; // Pipeline counter for column read
reg [7:0] r_left_byte = 0;
reg [7:0] r_right_byte = 0;

// Column Read Registers
reg [7:0] col_read_b0 = 0;
reg [7:0] col_read_b1 = 0;
reg [7:0] col_read_b2 = 0;
reg [7:0] col_read_b3 = 0;
reg [7:0] col_read_b4 = 0;
reg [7:0] col_read_b5 = 0;
reg [7:0] col_read_b6 = 0;
reg [7:0] col_read_b7 = 0;

// Local write registers
reg w_aligned_pipeline_flag = 0; // Pipeline flag for aligned write
reg [7:0] w_unaligned_pipeline_counter = 0; // Pipeline counter for unaligned write
reg [7:0] w_left_byte = 0;
reg [7:0] w_right_byte = 0;
reg [7:0] w_left_mask = 0;
reg [7:0] w_right_mask = 0;
reg [7:0] w_masked_left = 0;
reg [7:0] w_masked_right = 0;


// Combinational register logic ///////////////////////////
// Write address calculation
always @(w_xpos or w_ypos) begin
    w_addr <= (w_ypos * (H_PIXELS / 8)) + (w_xpos / 8);
end
// Read address calculation
always @(r_xpos or r_ypos) begin
    r_addr <= (r_ypos * (H_PIXELS / 8)) + (r_xpos / 8);
end
// Write Mask Calculations for unaligned writes
always @(w_xpos) begin
    w_left_mask = 8'hFF << (w_xpos % 8);
    w_right_mask = ~(8'hFF << (w_xpos % 8));
end
// Left and Right byte calculations for unaligned writes
always @(din or w_xpos) begin
    w_left_byte = din >> (w_xpos % 8);
    w_right_byte = din << (8 - (w_xpos % 8));
end


// Main read/write logic ////////////////////////
always @(posedge clk) begin
    // Reset logic
    if(rst) begin
        dout <= 8'h00;
        r_left_byte <= 8'h00;
        r_right_byte <= 8'h00;
        w_left_byte <= 8'h00;
        w_right_byte <= 8'h00;
        w_left_mask <= 8'h00;
        w_right_mask <= 8'h00;
        w_masked_left <= 8'h00;
        w_masked_right <= 8'h00;
        r_addr <= 12'h000;
        w_addr <= 12'h000;
    end

    // Clear read registers when re is low
    if (!re) begin
        dout <= 8'h00;
        r_data_valid <= 0;
        r_aligned_pipeline_flag <= 0;
        r_unaligned_pipeline_counter <= 0;
        r_column_pipeline_counter <= 0;
        r_left_byte <= 8'h00;
        r_right_byte <= 8'h00;
        col_read_b0 <= 8'h00;
        col_read_b1 <= 8'h00;
        col_read_b2 <= 8'h00;
        col_read_b3 <= 8'h00;
        col_read_b4 <= 8'h00;
        col_read_b5 <= 8'h00;
        col_read_b6 <= 8'h00;
        col_read_b7 <= 8'h00;
    end

    if(!we) begin
        w_data_valid <= 0;
        w_aligned_pipeline_flag <= 0;
        w_unaligned_pipeline_counter <= 0;
        ram_we <= 1'b0; // Disable write
        ram_w_addr <= 12'h000;
        ram_din <= 8'h00;
    end


    // Read Operation
    if (re) begin
        if (r_mode == 1'b0) begin // Horizontal read mode ////////////////////////
            if(r_xpos % 8 == 0) begin // Aligned read ////////////////////////////
                if(r_aligned_pipeline_flag == 0) begin
                    ram_r_addr <= r_addr;
                    r_aligned_pipeline_flag <= 1; // Wait one cycle for BRAM read
                end else begin
                    dout <= ram_dout; // Output data from BRAM
                    r_data_valid <= 1; // Indicate read data is valid
                end
            end else begin // Unaligned read - assemble from two bytes (one if per clock cycle)
                // Set the read address for the left byte
                if (r_unaligned_pipeline_counter == 0) begin
                    ram_r_addr <= r_addr;
                    r_unaligned_pipeline_counter <= 1; // Wait one cycle for left byte
                // Get the left byte and set read address for right byte
                end else if (r_unaligned_pipeline_counter == 1) begin
                    r_left_byte <= ram_dout;
                    ram_r_addr <= r_addr + 1;
                    r_unaligned_pipeline_counter <= 2; // Wait one cycle for right byte
                // Get the right byte
                end else if (r_unaligned_pipeline_counter == 2) begin
                    r_right_byte <= ram_dout;
                    r_unaligned_pipeline_counter <= 3; 
                end else begin
                    // Combine left and right bytes into output
                    dout <= (r_left_byte << (r_xpos % 8)) | (r_right_byte >> (8 - (r_xpos % 8)));
                    r_data_valid <= 1; // Indicate read data is valid
                end
            end
            ///////////////////////////////////////////////////////////////
        end else begin
            //Column read mode
            // Pipeline reads one byte per clock cycle for 8 cycles
            case (r_column_pipeline_counter)
                0: begin // Set first read address
                    ram_r_addr <= r_addr;
                    r_column_pipeline_counter <= 1;
                end
                1: begin // Get first byte
                    col_read_b0 <= ram_dout;
                    ram_r_addr <= r_addr + (H_PIXELS / 8);
                    r_column_pipeline_counter <= 2;
                end
                2: begin // Get second byte
                    col_read_b1 <= ram_dout;
                    ram_r_addr <= r_addr + 2*(H_PIXELS / 8);
                    r_column_pipeline_counter <= 3;
                end
                3: begin // Get third byte
                    col_read_b2 <= ram_dout;
                    ram_r_addr <= r_addr + 3*(H_PIXELS / 8);
                    r_column_pipeline_counter <= 4;
                end
                4: begin // Get fourth byte
                    col_read_b3 <= ram_dout;
                    ram_r_addr <= r_addr + 4*(H_PIXELS / 8);
                    r_column_pipeline_counter <= 5;
                end
                5: begin // Get fifth byte
                    col_read_b4 <= ram_dout;
                    ram_r_addr <= r_addr + 5*(H_PIXELS / 8);
                    r_column_pipeline_counter <= 6;
                end
                6: begin // Get sixth byte
                    col_read_b5 <= ram_dout;
                    ram_r_addr <= r_addr + 6*(H_PIXELS / 8);
                    r_column_pipeline_counter <= 7;
                end
                7: begin // Get seventh byte
                    col_read_b6 <= ram_dout;
                    ram_r_addr <= r_addr + 7*(H_PIXELS / 8);
                    r_column_pipeline_counter <= 8;
                end
                8: begin // Get eighth byte
                    col_read_b7 <= ram_dout;
                    r_column_pipeline_counter <= 9;
                end
                default: begin // Assemble output byte
                    dout <= (col_read_b0 << (r_xpos % 8)) & 8'b10000000 |
                            ((col_read_b1 << (r_xpos % 8)) & 8'b10000000) >> 1 |
                            ((col_read_b2 << (r_xpos % 8)) & 8'b10000000) >> 2 |
                            ((col_read_b3 << (r_xpos % 8)) & 8'b10000000) >> 3 |
                            ((col_read_b4 << (r_xpos % 8)) & 8'b10000000) >> 4 |
                            ((col_read_b5 << (r_xpos % 8)) & 8'b10000000) >> 5 |
                            ((col_read_b6 << (r_xpos % 8)) & 8'b10000000) >> 6 |
                            ((col_read_b7 << (r_xpos % 8)) & 8'b10000000) >> 7 ;
                    r_data_valid <= 1; // Indicate read data is valid
                end
            endcase // End column read mode
        end
    end

    // Write Operation
    if (we) begin
        if(w_xpos % 8 == 0) begin // Aligned Write ////////////////////////////
            if(w_aligned_pipeline_flag == 0) begin
                ram_w_addr <= w_addr;
                ram_din <= din;
                ram_we <= 1'b1; // Enable write
                w_aligned_pipeline_flag <= 1; // Wait one cycle for BRAM write
            end else begin
                w_data_valid <= 1; // Indicate write data accepted
                ram_we <= 1'b0; // Disable write
            end
        end else begin
            // Unaligned write - Pipeline to write two bytes
            // Must first read the left and right bytes from RAM, then mask them before writing new values back
            case (w_unaligned_pipeline_counter)
                0: begin // First cycle - Set read address for left byte
                    ram_r_addr <= w_addr;
                    w_unaligned_pipeline_counter <= 1;
                end
                1: begin // Second cycle - Read the left byte, mask, and set read address for right byte
                    w_masked_left <= (ram_dout & w_left_mask);
                    ram_r_addr <= w_addr + 1;
                    w_unaligned_pipeline_counter <= 2;
                end
                2: begin // Third cycle - Read the right byte and mask it
                    w_masked_right <= (ram_dout & w_right_mask);
                    w_unaligned_pipeline_counter <= 3;
                end
                3: begin // Fourth cycle - Write the combined left byte
                    ram_din <= w_masked_left | w_left_byte; // w_left_byte calculated combinationally above
                    ram_w_addr <= w_addr;
                    ram_we <= 1'b1; // Enable write
                    w_unaligned_pipeline_counter <= 4;
                end
                4: begin // Fifth cycle - Write the combined right byte
                    ram_din <= w_masked_right | w_right_byte; // w_right_byte calculated combinationally above
                    ram_w_addr <= w_addr + 1;
                    ram_we <= 1'b1; // Enable write
                    w_unaligned_pipeline_counter <= 5;
                end
                default: begin // Sixth cycle - Finish write and report done
                    w_data_valid <= 1; // Indicate write data accepted
                    ram_we <= 1'b0; // Disable write
                end
            endcase
        end
    end
end

endmodule