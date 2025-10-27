//TODO: Can prevent out of bounds writes by clamping w_xpos and w_ypos in an always block!
// TODO: need to not write while reading, because unaligned writes use the read port to read existing data first
// TODO: adjust other read modes to handle two clock delay on RAM access
`default_nettype none

module framebuffer_monochrome
(
    input wire clk, // Module clock input
    input wire rst, // Module reset input (active high)
    output reg rst_complete = 0, // High when framebuffer memory has been cleared after reset
    output reg busy = 0, // High when framebuffer is busy (resetting or processing a read/write)

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

localparam H_PIXELS = 128; // Horizontal resolution in pixels
localparam V_PIXELS = 64; // Vertical resolution in pixels
localparam FRAMEBUFFER_DEPTH = (H_PIXELS / 8) * V_PIXELS; // Framebuffer size in bytes

// Registers for dual port BRAM interface
reg [11:0] ram_addr = 0; // Read/Write address (12 bits to cover 1024 bytes)
reg [7:0] ram_din = 0; // Data input to BRAM
wire [7:0] ram_dout; // Data output from BRAM
reg ram_we = 0; // Write enable to BRAM
reg reset_active = 0; // Indicates framebuffer clear is in progress
reg [11:0] reset_addr = 0; // Address pointer used during framebuffer clear

// Single Port BRAM Instance used for Framebuffer Storage
single_port_bram #(
    .ADDR_WIDTH(12), // 128*64/8 = 1024 bytes = 2^10, so 12 bits is enough
    .DATA_WIDTH(8),
    .DEPTH(FRAMEBUFFER_DEPTH) // Total framebuffer size in bytes
) bram (
    .clk(clk),
    .we(ram_we),
    .addr(ram_addr),
    .din(ram_din),
    .dout(ram_dout)
);


// Address calculation registers
wire [11:0] r_addr = (r_ypos * (H_PIXELS / 8)) + (r_xpos / 8);
wire [11:0] w_addr = (w_ypos * (H_PIXELS / 8)) + (w_xpos / 8);

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
reg w_aligned_pipeline_counter = 0; // Pipeline flag for aligned write
reg [7:0] w_unaligned_pipeline_counter = 0; // Pipeline counter for unaligned write
wire [7:0] w_left_byte = din << (w_xpos % 8);
wire [7:0] w_right_byte = (w_xpos % 8 == 0) ? 8'h00 : (din >> (8 - (w_xpos % 8)));  // bits to write into right byte (lower part)
wire [7:0] w_right_mask = 8'hFF << (w_xpos % 8);
wire [7:0] w_left_mask = ~(8'hFF << (w_xpos % 8));
reg [7:0] w_masked_left = 0;
reg [7:0] w_masked_right = 0;


// Main read/write logic ////////////////////////
always @(posedge clk) begin

    // Parent should raise reset signal high, then lower and wait for rst_complete to go high
    if (rst) begin 
        reset_active <= 1'b1;
        busy <= 1'b1;
        reset_addr <= 12'd0;
        rst_complete <= 1'b0;
        // Clear all other registers
        dout <= 8'h00;
        r_data_valid <= 0;
        w_data_valid <= 0;
        r_left_byte <= 8'h00;
        r_right_byte <= 8'h00;
        w_masked_left <= 8'h00;
        w_masked_right <= 8'h00;
        r_aligned_pipeline_flag <= 0;
        r_unaligned_pipeline_counter <= 0;
        r_column_pipeline_counter <= 0;
        col_read_b0 <= 8'h00;
        col_read_b1 <= 8'h00;
        col_read_b2 <= 8'h00;
        col_read_b3 <= 8'h00;
        col_read_b4 <= 8'h00;
        col_read_b5 <= 8'h00;
        col_read_b6 <= 8'h00;
        col_read_b7 <= 8'h00;
        w_aligned_pipeline_counter <= 0;
        w_unaligned_pipeline_counter <= 0;
        ram_we <= 1'b0;
        ram_addr <= 12'h000;
        ram_din <= 8'h00;

    end else if (reset_active) begin // Wait to clear RAM until reset is deasserted
        // Clear framebuffer memory by walking every BRAM address with zero writes
        rst_complete <= 1'b0;
        ram_addr <= reset_addr;
        ram_din <= 8'h00;
        ram_we <= 1'b1;

        if (reset_addr == FRAMEBUFFER_DEPTH - 1) begin // If last address reached
            reset_active <= 1'b0;
            rst_complete <= 1'b1;
            ram_we <= 1'b0;
            ram_addr <= 12'h000;
            busy <= 1'b0;
        end else begin // Not last address yet, increment address
            reset_addr <= reset_addr + 12'd1; // Increment by one (000000000001)
        end

    // //////////////// End reset handling //////////////////////

    end else begin // Normal operation (not reset)
        
        if(!re && !we) begin // Only not busy if not reading or writing
            busy <= 1'b0;
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
            w_aligned_pipeline_counter <= 0;
            w_unaligned_pipeline_counter <= 0;
            ram_we <= 1'b0; // Disable write
            ram_din <= 8'h00;
        end

        // Read Operation
        if (re) begin
            busy <= 1'b1;
            ram_we <= 1'b0; // Ensure write is disabled during read
            if (r_mode == 1'b0) begin // Horizontal read mode ////////////////////////
                if(r_xpos % 8 == 0) begin // Aligned read ////////////////////////////
                    case(r_aligned_pipeline_flag)
                        0: begin // First cycle - Set read address
                            ram_addr <= r_addr;
                            r_aligned_pipeline_flag <= 1; // Wait two cycles for BRAM read
                        end
                        1: begin // Second cycle - Wait for BRAM
                            r_aligned_pipeline_flag <= 2; // One more cycle...
                        end
                        default: begin // Third cycle - Output data
                            dout <= ram_dout; // Output data from BRAM
                            r_data_valid <= 1; // Indicate read data is valid
                        end
                    endcase
                end else begin // Unaligned read pipeline - assemble from two bytes 
                    // Set the read address for the left byte
                    case (r_unaligned_pipeline_counter)
                        0: begin // First cycle - Set read address for left byte
                            ram_addr <= r_addr; // Set left byte address
                            r_unaligned_pipeline_counter <= 1; // Wait two cycles for left byte
                        end
                        1: begin // Second cycle - Set read address for right byte
                            ram_addr <= r_addr + 1; // Set right byte address (data will be ready in two more clocks)
                            r_unaligned_pipeline_counter <= 2; // One more cycle... 
                        end
                        2: begin // Third cycle - Read left byte
                            r_left_byte <= ram_dout;
                            r_unaligned_pipeline_counter <= 3; // Wait one cycle for right byte
                        end
                        3: begin // Fourth cycle - Read right byte
                            // Check if we rolled off the right edge of the screen or the bottom
                            if(((r_addr + 1) % (H_PIXELS / 8) == 0) || (r_addr + 1) >= FRAMEBUFFER_DEPTH) begin
                                r_right_byte <= 8'h00; // If so, return 0s for right byte
                            end else begin
                                r_right_byte <= ram_dout;
                            end
                            r_unaligned_pipeline_counter <= 4; 
                        end
                        default: begin // Fifth cycle - Combine and output
                            // Combine left and right bytes into output
                            dout <= (r_left_byte << (r_xpos % 8)) | (r_right_byte >> (8 - (r_xpos % 8)));
                            r_data_valid <= 1; // Indicate read data is valid
                        end
                    endcase
                end
                ///////////////////////////////////////////////////////////////
            end else begin
                //Column read mode

                //TODO: Don't read past the end of the framebuffer!
                // Pipeline reads one byte per clock cycle for 8 cycles
                case (r_column_pipeline_counter)
                    0: begin // Set first read address
                        ram_addr <= r_addr;
                        r_column_pipeline_counter <= 1;
                    end
                    1: begin // Get first byte
                        //col_read_b0 <= ram_dout;
                        ram_addr <= r_addr + (H_PIXELS / 8);
                        r_column_pipeline_counter <= 2;
                    end
                    2: begin // Get second byte
                        col_read_b0 <= ram_dout;
                        ram_addr <= r_addr + 2*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 3;
                    end
                    3: begin // Get third byte
                        col_read_b1 <= ram_dout;
                        ram_addr <= r_addr + 3*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 4;
                    end
                    4: begin // Get fourth byte
                        col_read_b2 <= ram_dout;
                        ram_addr <= r_addr + 4*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 5;
                    end
                    5: begin // Get fifth byte
                        col_read_b3 <= ram_dout;
                        ram_addr <= r_addr + 5*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 6;
                    end
                    6: begin // Get sixth byte
                        col_read_b4 <= ram_dout;
                        ram_addr <= r_addr + 6*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 7;
                    end
                    7: begin // Get seventh byte
                        col_read_b5 <= ram_dout;
                        ram_addr <= r_addr + 7*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 8;
                    end
                    8: begin // Get eighth byte
                        col_read_b6 <= ram_dout;
                        r_column_pipeline_counter <= 9;
                    end
                    9: begin // Get ninth byte
                        col_read_b7 <= ram_dout;
                        r_column_pipeline_counter <= 10;
                    end
                    default: begin // Assemble output byte
                    // Column read byte is returned LSB first
                        dout <= (col_read_b7 << (r_xpos % 8)) & 8'b10000000 |
                                ((col_read_b6 << (r_xpos % 8)) & 8'b10000000) >> 1 |
                                ((col_read_b5 << (r_xpos % 8)) & 8'b10000000) >> 2 |
                                ((col_read_b4 << (r_xpos % 8)) & 8'b10000000) >> 3 |
                                ((col_read_b3 << (r_xpos % 8)) & 8'b10000000) >> 4 |
                                ((col_read_b2 << (r_xpos % 8)) & 8'b10000000) >> 5 |
                                ((col_read_b1 << (r_xpos % 8)) & 8'b10000000) >> 6 |
                                ((col_read_b0 << (r_xpos % 8)) & 8'b10000000) >> 7 ;
                        r_data_valid <= 1; // Indicate read data is valid
                    end
                endcase // End column read mode
            end
        end

        // Write Operation
        if (we && !re) begin // Prevent writes during reads
            busy <= 1'b1;
            if(w_xpos % 8 == 0) begin // Aligned Write ////////////////////////////
                if(w_aligned_pipeline_counter == 0) begin
                    ram_addr <= w_addr;
                    ram_din <= din;
                    ram_we <= 1'b1; // Enable write
                    w_aligned_pipeline_counter <= 1; // Wait one cycle for BRAM write
                end else begin
                    w_data_valid <= 1; // Indicate write data accepted
                    ram_we <= 1'b0; // Disable write
                end
            end else begin
                // Unaligned write - Pipeline to write two bytes
                // Must first read the left and right bytes from RAM, then mask them before writing new values back
                case (w_unaligned_pipeline_counter)
                    0: begin // Zeroeth cycle - Set read address for left byte
                        ram_we <= 1'b0; // Ensure write is disabled during read
                        ram_addr <= w_addr;
                        w_unaligned_pipeline_counter <= 1;
                    end
                    1: begin // First cycle - Set read address for right byte
                        ram_addr <= w_addr + 1;
                        w_unaligned_pipeline_counter <= 2;
                    end
                    2: begin // Second cycle - Read the left byte and mask it
                        w_masked_left <= (ram_dout & w_left_mask);
                        w_unaligned_pipeline_counter <= 3;
                    end
                    3: begin // Third cycle - Read the right byte and mask it
                        w_masked_right <= (ram_dout & w_right_mask);
                        w_unaligned_pipeline_counter <= 4;
                    end
                    4: begin // Fourth cycle - Write the combined left byte
                        ram_din <= w_masked_left | w_left_byte; // w_left_byte calculated combinationally above
                        ram_addr <= w_addr;
                        ram_we <= 1'b1; // Enable write
                        w_unaligned_pipeline_counter <= 5;
                    end
                    5: begin // Fifth cycle - Write the combined right byte
                        ram_din <= w_masked_right | w_right_byte; // w_right_byte calculated combinationally above
                        ram_addr <= w_addr + 1;
                        // Check if we rolled off the right edge of the screen or the bottom
                        if(((w_addr + 1) % (H_PIXELS / 8) == 0) || (w_addr + 1) >= FRAMEBUFFER_DEPTH) begin
                            ram_we <= 1'b0; // If so, do not write the second byte
                        end else begin
                            ram_we <= 1'b1; // Enable write
                        end
                        w_unaligned_pipeline_counter <= 6;
                    end
                    default: begin // Sixth cycle - Finish write and report done
                        w_data_valid <= 1; // Indicate write data accepted
                        ram_we <= 1'b0; // Disable write
                    end
                endcase
            end
        end
    end
end

endmodule