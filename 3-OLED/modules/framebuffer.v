////////////////////////////////////////////////////////////////////////////////
// Monochrome framebuffer for 128x64 OLED panels.
//
// Provides byte-packed storage (8 pixels/byte) with pipelined read/write
// access. Supports aligned (byte) and unaligned pixel operations plus an
// 8-byte column read mode. Reset walks BRAM to clear all pixels before
// reporting rst_complete.
//
// Usage notes:
//  * Addressing: addr = (y * 16) + (x / 8); coordinates are pixel-based.
//  * Unaligned writes read-modify-write two bytes; avoid asserting WE during RE.
//  * Column reads stride by 16 bytes (one row) each cycle; pipeline latency is
//    11 cycles before dout becomes valid.
//  * Out-of-range accesses clamp to zero to protect framebuffer contents.
//  * Assert rst high long enough for the clear sweep; wait for rst_complete.
//  * w_data_valid / r_data_valid strobe high when operations finish.
//
// All timing assumes synchronous BRAM with two-cycle read latency.
////////////////////////////////////////////////////////////////////////////////

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

// Local read registers
reg [7:0] r_aligned_pipeline_counter = 0; // Pipeline counter for aligned read
reg [7:0] r_unaligned_pipeline_counter = 0; // Pipeline counter for unaligned read
reg [7:0] r_column_pipeline_counter = 0; // Pipeline counter for column read
reg [11:0] r_addr = 0;
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
reg [7:0] w_aligned_pipeline_counter = 0; // Pipeline counter for aligned write
reg [7:0] w_unaligned_pipeline_counter = 0; // Pipeline counter for unaligned write
reg [11:0] w_addr = 0; 
reg [7:0] w_left_mask = 0;
reg [7:0] w_right_mask = 0;
reg [7:0] w_left_byte = 0;
reg [7:0] w_right_byte = 0;
reg [7:0] w_masked_left = 0;
reg [7:0] w_masked_right = 0;

// Combinational calculations for addresses and masks
always @(posedge clk) begin
    r_addr <= (r_ypos * (H_PIXELS / 8)) + (r_xpos / 8);
    w_addr <= (w_ypos * (H_PIXELS / 8)) + (w_xpos / 8);
    w_left_mask <= (8'hFF << (8 - (w_xpos % 8)));
    w_right_mask <= ~(8'hFF << (8 - (w_xpos % 8)));
    w_left_byte <= din >> (w_xpos % 8);
    w_right_byte <= (w_xpos % 8 == 0) ? 8'h00 : (din << (8 - (w_xpos % 8)));  // bits to write into right byte (lower part)
end


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
        r_aligned_pipeline_counter <= 0;
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

        if (reset_addr >= FRAMEBUFFER_DEPTH) begin // If last address reached
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
            r_aligned_pipeline_counter <= 0;
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
            w_unaligned_pipeline_counter <= 0; // Clear write pipelines if interrupt to read
            w_aligned_pipeline_counter <= 0;
            
            if (r_mode == 1'b0) begin // Horizontal read mode ////////////////////////
                if(r_xpos % 8 == 0) begin // Aligned read ////////////////////////////
                    case(r_aligned_pipeline_counter)
                        0: begin 
                            r_aligned_pipeline_counter <= 1; // Cycle 0 - wait for address to stabilize
                        end
                        1: begin
                            ram_addr <= r_addr; // Set read address
                            r_aligned_pipeline_counter <= 2; // Cycle 1 - wait for BRAM read
                        end
                        2: begin // Cycle 2 - wait for BRAM
                            r_aligned_pipeline_counter <= 3;
                        end
                        default: begin // Cycle 3 - output data
                            dout <= ram_dout; // Output data from BRAM
                            r_data_valid <= 1; // Indicate read data is valid
                        end
                    endcase
                end else begin // Unaligned read pipeline - assemble from two bytes 
                    // Set the read address for the left byte
                    case (r_unaligned_pipeline_counter)
                        0: begin // Cycle 0 - wait for r_addr to settle
                            r_unaligned_pipeline_counter <= 1;
                        end
                        1: begin // Cycle 1 - set read address for left byte
                            ram_addr <= r_addr; // Set left byte address
                            r_unaligned_pipeline_counter <= 2; // Wait two cycles for left byte
                        end
                        2: begin // Cycle 2 - set read address for right byte
                            ram_addr <= r_addr + 1; // Set right byte address (data will be ready in two more clocks)
                            r_unaligned_pipeline_counter <= 3;
                        end
                        3: begin // Cycle 3 - read left byte
                            r_left_byte <= ram_dout;
                            r_unaligned_pipeline_counter <= 4; // Wait one cycle for right byte
                        end
                        4: begin // Cycle 4 - read right byte
                            // Check if we rolled off the right edge of the screen or the bottom
                            if(((r_addr + 1) % (H_PIXELS / 8) == 0) || (r_addr + 1) >= FRAMEBUFFER_DEPTH) begin
                                r_right_byte <= 8'h00; // If so, return 0s for right byte
                            end else begin
                                r_right_byte <= ram_dout;
                            end
                            r_unaligned_pipeline_counter <= 5; 
                        end
                        default: begin // Cycle 5 - combine and output
                            // Combine left and right bytes into output
                            dout <= (r_left_byte << (r_xpos % 8)) | (r_right_byte >> (8 - (r_xpos % 8)));
                            r_data_valid <= 1; // Indicate read data is valid
                        end
                    endcase
                end
                ///////////////////////////////////////////////////////////////
            end else begin
                //Column read mode
                case (r_column_pipeline_counter)
                    0: begin // Cycle 0 - wait for r_addr to settle
                        r_column_pipeline_counter <= 1;
                    end
                    1: begin // Cycle 1 - set first read address
                        ram_addr <= r_addr;
                        r_column_pipeline_counter <= 2;
                    end
                    2: begin // Cycle 2 - prepare to get first byte
                        ram_addr <= r_addr + (H_PIXELS / 8);
                        r_column_pipeline_counter <= 3;
                    end
                    3: begin // Cycle 3 - get second byte
                        col_read_b0 <= ram_dout;
                        ram_addr <= r_addr + 2*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 4;
                    end
                    4: begin // Cycle 4 - get third byte
                        if ((r_addr + (H_PIXELS / 8)) >= FRAMEBUFFER_DEPTH) begin
                            col_read_b1 <= 8'h00;
                        end else begin
                            col_read_b1 <= ram_dout;
                        end
                        ram_addr <= r_addr + 3*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 5;
                    end
                    5: begin // Cycle 5 - get fourth byte
                        if ((r_addr + 2*(H_PIXELS / 8)) >= FRAMEBUFFER_DEPTH) begin
                            col_read_b2 <= 8'h00;
                        end else begin
                            col_read_b2 <= ram_dout;
                        end
                        ram_addr <= r_addr + 4*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 6;
                    end
                    6: begin // Cycle 6 - get fifth byte
                        if ((r_addr + 3*(H_PIXELS / 8)) >= FRAMEBUFFER_DEPTH) begin
                            col_read_b3 <= 8'h00;
                        end else begin
                            col_read_b3 <= ram_dout;
                        end
                        ram_addr <= r_addr + 5*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 7;
                    end
                    7: begin // Cycle 7 - get sixth byte
                        if ((r_addr + 4*(H_PIXELS / 8)) >= FRAMEBUFFER_DEPTH) begin
                            col_read_b4 <= 8'h00;
                        end else begin
                            col_read_b4 <= ram_dout;
                        end
                        ram_addr <= r_addr + 6*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 8;
                    end
                    8: begin // Cycle 8 - get seventh byte
                        if ((r_addr + 5*(H_PIXELS / 8)) >= FRAMEBUFFER_DEPTH) begin
                            col_read_b5 <= 8'h00;
                        end else begin
                            col_read_b5 <= ram_dout;
                        end
                        ram_addr <= r_addr + 7*(H_PIXELS / 8);
                        r_column_pipeline_counter <= 9;
                    end
                    9: begin // Cycle 9 - get eighth byte
                        if ((r_addr + 6*(H_PIXELS / 8)) >= FRAMEBUFFER_DEPTH) begin
                            col_read_b6 <= 8'h00;
                        end else begin
                            col_read_b6 <= ram_dout;
                        end
                        r_column_pipeline_counter <= 10;
                    end
                    10: begin // Cycle 10 - get ninth byte
                        if ((r_addr + 7*(H_PIXELS / 8)) >= FRAMEBUFFER_DEPTH) begin
                            col_read_b7 <= 8'h00;
                        end else begin
                            col_read_b7 <= ram_dout;
                        end
                        r_column_pipeline_counter <= 11;
                    end
                    default: begin // Cycle 11 - assemble output byte
                        // Extract bit at r_xpos % 8 from each column byte (LSB first)
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
                case (w_aligned_pipeline_counter)
                    0: begin // Cycle 0 - wait for w_addr to stabilize
                        w_aligned_pipeline_counter <= 1;
                    end
                    1: begin // Cycle 1 - set address and write
                        ram_addr <= w_addr;
                        ram_din <= din;
                        ram_we <= 1'b1; // Enable write
                        w_aligned_pipeline_counter <= 2;
                    end
                    default: begin // Cycle 2 - indicate done
                        w_data_valid <= 1; // Indicate write data accepted
                        ram_we <= 1'b0; // Disable write
                    end
                endcase
            end else begin
                // Unaligned write - Pipeline to write two bytes
                // Must first read the left and right bytes from RAM, then mask them before writing new values back
                case (w_unaligned_pipeline_counter)
                    0: begin // Cycle 0 - blank cycle
                        w_unaligned_pipeline_counter <= 1;
                    end
                    1: begin // Cycle 1 - set read address for left byte
                        ram_we <= 1'b0; // Ensure write is disabled during read
                        ram_addr <= w_addr;
                        w_unaligned_pipeline_counter <= 2;
                    end
                    2: begin // Cycle 2 - set read address for right byte
                        ram_addr <= w_addr + 1;
                        w_unaligned_pipeline_counter <= 3;
                    end
                    3: begin // Cycle 3 - read the left byte and mask it
                        w_masked_left <= (ram_dout & w_left_mask);
                        w_unaligned_pipeline_counter <= 4;
                    end
                    4: begin // Cycle 4 - read the right byte and mask it
                        w_masked_right <= (ram_dout & w_right_mask);
                        w_unaligned_pipeline_counter <= 5;
                    end
                    5: begin // Cycle 5 - write the combined left byte
                        ram_din <= w_masked_left | w_left_byte; // w_left_byte calculated combinationally above
                        ram_addr <= w_addr;
                        ram_we <= 1'b1; // Enable write
                        w_unaligned_pipeline_counter <= 6;
                    end
                    6: begin // Cycle 6 - write the combined right byte
                        ram_din <= w_masked_right | w_right_byte; // w_right_byte calculated combinationally above
                        ram_addr <= w_addr + 1;
                        // Check if we rolled off the right edge of the screen or the bottom
                        if(((w_addr + 1) % (H_PIXELS / 8) == 0) || (w_addr + 1) >= FRAMEBUFFER_DEPTH) begin
                            ram_we <= 1'b0; // If so, do not write the second byte
                        end else begin
                            ram_we <= 1'b1; // Enable write
                        end
                        w_unaligned_pipeline_counter <= 7;
                    end
                    default: begin // Cycle 7 - indicate done
                        w_data_valid <= 1; // Indicate write data accepted
                        ram_we <= 1'b0; // Disable write
                    end
                endcase
            end
        end
    end
end

endmodule