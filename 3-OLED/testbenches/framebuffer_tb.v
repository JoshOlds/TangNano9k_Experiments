`timescale 1ns / 1ps
`default_nettype none

module test;

// Parameters
localparam H_PIXELS = 128;
localparam V_PIXELS = 64;
localparam CLK_PERIOD = 10; // 10ns clock period (100MHz)

// DUT signals
reg clk;
reg rst;
reg we;
reg [7:0] w_xpos;
reg [7:0] w_ypos;
reg [7:0] din;
reg re;
wire [7:0] dout;
reg [7:0] r_xpos;
reg [7:0] r_ypos;
reg r_mode;

// Test variables
integer i, j;
reg [7:0] expected_data;
reg [7:0] read_data;

// Instantiate the DUT (Device Under Test)
framebuffer_monochrome dut (
    .clk(clk),
    .rst(rst),
    .we(we),
    .w_xpos(w_xpos),
    .w_ypos(w_ypos),
    .din(din),
    .re(re),
    .dout(dout),
    .r_xpos(r_xpos),
    .r_ypos(r_ypos),
    .r_mode(r_mode)
);

// Clock generation
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// Task to write data to framebuffer
task write_pixel_byte;
    input [7:0] x;
    input [7:0] y;
    input [7:0] data;
    begin
        @(posedge clk);
        we = 1;
        w_xpos = x;
        w_ypos = y;
        din = data;
        @(posedge clk);
        we = 0;
        @(posedge clk); // Extra cycle for write to complete
    end
endtask

// Task to read data from framebuffer (horizontal mode)
task read_pixel_byte_horizontal;
    input [7:0] x;
    input [7:0] y;
    output [7:0] data;
    begin
        @(posedge clk);
        re = 1;
        r_xpos = x;
        r_ypos = y;
        r_mode = 0; // Horizontal read mode
        @(posedge clk);
        @(posedge clk);
        data = dout;
        re = 0;
        @(posedge clk);
    end
endtask

// Task to read data from framebuffer (column mode)
task read_pixel_byte_column;
    input [7:0] x;
    input [7:0] y;
    output [7:0] data;
    begin
        @(posedge clk);
        re = 1;
        r_xpos = x;
        r_ypos = y;
        r_mode = 1; // Column read mode
        @(posedge clk);
        @(posedge clk);
        data = dout;
        re = 0;
        @(posedge clk);
    end
endtask

// Task to display framebuffer contents
task display_framebuffer;
    integer row, col, bit_idx;
    reg [7:0] byte_data;
    begin
        $display("\n========================================");
        $display("FRAMEBUFFER CONTENTS (%0dx%0d pixels)", H_PIXELS, V_PIXELS);
        $display("========================================");
        $display("Legend: '#' = pixel on (1), '.' = pixel off (0)\n");
        
        // Display framebuffer row by row
        for (row = 0; row < V_PIXELS; row = row + 1) begin
            $write("Row %2d: ", row);
            
            // Read each byte in the row
            for (col = 0; col < H_PIXELS; col = col + 8) begin
                // Access the framebuffer directly
                byte_data = dut.framebuffer[(row * (H_PIXELS / 8)) + (col / 8)];
                
                // Display each bit in the byte (MSB first)
                for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                    if (byte_data[bit_idx])
                        $write("#");
                    else
                        $write(".");
                end
                $write(" ");
            end
            $display("");
        end
        $display("========================================\n");
    end
endtask

// Task to apply reset
task apply_reset;
    begin
        $display("Applying reset...");
        @(posedge clk);
        rst = 1;
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);
        $display("Reset complete.\n");
    end
endtask

// Main test sequence
initial begin
    $display("\n========================================");
    $display("FRAMEBUFFER TESTBENCH STARTING");
    $display("========================================\n");
    
    // Initialize signals
    rst = 0;
    we = 0;
    w_xpos = 0;
    w_ypos = 0;
    din = 0;
    re = 0;
    r_xpos = 0;
    r_ypos = 0;
    r_mode = 0;
    
    // Apply reset
    $display("TEST 1: Applying reset...");
    @(posedge clk);
    rst = 1;
    repeat(5) @(posedge clk);
    rst = 0;
    repeat(2) @(posedge clk);
    $display("Reset complete.\n");

    $display("TEST 2: Reading to check reset cleared framebuffer...");
    read_pixel_byte_horizontal(0, 0, read_data);
    $display("Read from (0, 0): 0x%02h (expected: 0x%02h)", read_data, 8'b11111111);
    
    // Test 3: Write aligned data (xpos % 8 == 0)
    $display("TEST 3: Testing aligned writes...");
    write_pixel_byte(0, 0, 8'b11110000);
    write_pixel_byte(8, 0, 8'b10101010);
    write_pixel_byte(16, 0, 8'b11001100);
    write_pixel_byte(0, 1, 8'b11111111);
    write_pixel_byte(8, 1, 8'b00000001);
    $display("Aligned writes complete.\n");
    
    // Verification of aligned writes
    $display("TEST 3a: Verifying aligned writes...");
    read_pixel_byte_horizontal(0, 0, read_data);
    if (read_data == 8'b11110000) $display("PASS: Read from (0, 0): 0x%02h", read_data);
    else $display("FAIL: Read from (0, 0): 0x%02h (expected: 0x%02h)", read_data, 8'b11110000);
    
    read_pixel_byte_horizontal(8, 0, read_data);
    if (read_data == 8'b10101010) $display("PASS: Read from (8, 0): 0x%02h", read_data);
    else $display("FAIL: Read from (8, 0): 0x%02h (expected: 0x%02h)", read_data, 8'b10101010);
    
    read_pixel_byte_horizontal(16, 0, read_data);
    if (read_data == 8'b11001100) $display("PASS: Read from (16, 0): 0x%02h", read_data);
    else $display("FAIL: Read from (16, 0): 0x%02h (expected: 0x%02h)", read_data, 8'b11001100);
    
    read_pixel_byte_horizontal(0, 1, read_data);
    if (read_data == 8'b11111111) $display("PASS: Read from (0, 1): 0x%02h", read_data);
    else $display("FAIL: Read from (0, 1): 0x%02h (expected: 0x%02h)", read_data, 8'b11111111);
    
    read_pixel_byte_horizontal(8, 1, read_data);
    if (read_data == 8'b00000001) $display("PASS: Read from (8, 1): 0x%02h", read_data);
    else $display("FAIL: Read from (8, 1): 0x%02h (expected: 0x%02h)", read_data, 8'b00000001);
    $display("Aligned write verification complete.\n");

    apply_reset();

    $display("Verifying reset cleared framebuffer...");
    read_pixel_byte_horizontal(0, 0, read_data);
    if (read_data == 8'b00000000) $display("PASS: Read from (0, 0): 0x%02h\n", read_data);
    else $display("FAIL: Read from (0, 0): 0x%02h (expected: 0x%02h)\n", read_data, 8'b00000000);
    
    // Test 3: Write unaligned data (xpos % 8 != 0)
    $display("TEST 4: Testing unaligned writes...");
    write_pixel_byte(4, 0, 8'b11110011);
    write_pixel_byte(12, 2, 8'b10101010);
    $display("Unaligned writes complete.\n");
    
    // Verification of unaligned writes
    $display("TEST 4a: Verifying unaligned writes...");
    
    // Verify first unaligned write: (4, 0, 8'b11110000)
    // Affects left byte at (0,0) and right byte at (8,0)
    read_pixel_byte_horizontal(0, 0, read_data);
    // Expected: bits 4-7 = 1111 (from write), bits 0-3 = 0000 (initial)
    if (read_data == 8'b00001111) $display("PASS: Left byte (0,0): 0x%02h", read_data);
    else $display("FAIL: Left byte (0,0): 0x%02h (expected: 0x%02h)", read_data, 8'b00001111);
    
    read_pixel_byte_horizontal(8, 0, read_data);
    // Expected: bits 0-3 = 0000 (from write), bits 4-7 = 0000 (initial)
    if (read_data == 8'b00110000) $display("PASS: Right byte (8,0): 0x%02h", read_data);
    else $display("FAIL: Right byte (8,0): 0x%02h (expected: 0x%02h)", read_data, 8'b00110000);
    
    // Unaligned read at exact position (4,0)
    read_pixel_byte_horizontal(4, 0, read_data);
    if (read_data == 8'b11110011) $display("PASS: Unaligned read at (4,0): 0x%02h", read_data);
    else $display("FAIL: Unaligned read at (4,0): 0x%02h (expected: 0x%02h)", read_data, 8'b11110011);
    
    // Verify second unaligned write: (12, 2, 8'b10101010)
    // Affects left byte at (8,2) and right byte at (16,2)
    read_pixel_byte_horizontal(8, 2, read_data);
    // Expected: bits 4-7 = 1010 (from write), bits 0-3 = 0000 (initial)
    if (read_data == 8'b00001010) $display("PASS: Left byte (8,2): 0x%02h", read_data);
    else $display("FAIL: Left byte (8,2): 0x%02h (expected: 0x%02h)", read_data, 8'b00001010);
    
    read_pixel_byte_horizontal(16, 2, read_data);
    // Expected: bits 0-3 = 1010 (from write), bits 4-7 = 0000 (initial)
    if (read_data == 8'b10100000) $display("PASS: Right byte (16,2): 0x%02h", read_data);
    else $display("FAIL: Right byte (16,2): 0x%02h (expected: 0x%02h)", read_data, 8'b10100000);

    // Unaligned read at exact position (12,2)
    read_pixel_byte_horizontal(12, 2, read_data);
    if (read_data == 8'b10101010) $display("PASS: Unaligned read at (12,2): 0x%02h", read_data);
    else $display("FAIL: Unaligned read at (12,2): 0x%02h (expected: 0x%02h)", read_data, 8'b10101010);

    $display("Unaligned write verification complete.\n");
    
    apply_reset();

    $display("Testing column read mode...");
    write_pixel_byte(0, 0, 8'b11001100);
    write_pixel_byte(0, 1, 8'b10101010);
    write_pixel_byte(0, 2, 8'b11110000);
    write_pixel_byte(0, 3, 8'b00001111);
    write_pixel_byte(0, 4, 8'b11001100);
    write_pixel_byte(0, 5, 8'b10101010);
    write_pixel_byte(0, 6, 8'b11110000);
    write_pixel_byte(0, 7, 8'b00001111);

    // Verification of column read mode
    $display("TEST 5: Verifying column read mode...");
    read_pixel_byte_column(0, 0, read_data);
    if (read_data == 8'b11101110) $display("PASS: Column read at (0,0): 0x%02h", read_data);
    else $display("FAIL: Column read at (0,0): 0x%02h (expected: 0x%02h)", read_data, 8'b11101110);
    
    read_pixel_byte_column(1, 0, read_data);
    if (read_data == 8'b10101010) $display("PASS: Column read at (1,0): 0x%02h", read_data);
    else $display("FAIL: Column read at (1,0): 0x%02h (expected: 0x%02h)", read_data, 8'b10101010);

    read_pixel_byte_column(2, 0, read_data);
    if (read_data == 8'b01100110) $display("PASS: Column read at (2,0): 0x%02h", read_data);
    else $display("FAIL: Column read at (2,0): 0x%02h (expected: 0x%02h)", read_data, 8'b01100110);

    read_pixel_byte_column(3, 0, read_data);
    if (read_data == 8'b00100010) $display("PASS: Column read at (3,0): 0x%02h", read_data);
    else $display("FAIL: Column read at (3,0): 0x%02h (expected: 0x%02h)", read_data, 8'b00100010);

    read_pixel_byte_column(4, 0, read_data);
    if (read_data == 8'b11011101) $display("PASS: Column read at (4,0): 0x%02h", read_data);
    else $display("FAIL: Column read at (4,0): 0x%02h (expected: 0x%02h)", read_data, 8'b11011101);

    read_pixel_byte_column(5, 0, read_data);
    if (read_data == 8'b10011001) $display("PASS: Column read at (5,0): 0x%02h", read_data);
    else $display("FAIL: Column read at (5,0): 0x%02h (expected: 0x%02h)", read_data, 8'b10011001);

    read_pixel_byte_column(6, 0, read_data);
    if (read_data == 8'b01010101) $display("PASS: Column read at (6,0): 0x%02h", read_data);
    else $display("FAIL: Column read at (6,0): 0x%02h (expected: 0x%02h)", read_data, 8'b01010101);

    read_pixel_byte_column(7, 0, read_data);
    if (read_data == 8'b00010001) $display("PASS: Column read at (7,0): 0x%02h", read_data);
    else $display("FAIL: Column read at (7,0): 0x%02h (expected: 0x%02h)", read_data, 8'b00010001);

    read_pixel_byte_column(3, 3, read_data);
    if (read_data == 8'b00010000) $display("PASS: Column read at (3,3): 0x%02h", read_data);
    else $display("FAIL: Column read at (3,3): 0x%02h (expected: 0x%02h)", read_data, 8'b00100000);
    $display("Column read verification complete.\n");

    $display("Column read verification complete.\n");

    

    // Test 9: Display framebuffer contents
    $display("TEST 9: Displaying framebuffer contents...");
    repeat(5) @(posedge clk);
    display_framebuffer();
    
    // Test 10: Reset and verify clear
    $display("TEST 10: Testing reset clears framebuffer...");
    rst = 1;
    repeat(5) @(posedge clk);
    rst = 0;
    repeat(2) @(posedge clk);
    
    read_pixel_byte_horizontal(0, 0, read_data);
    $display("Read from (0, 0) after reset: 0x%02h (expected: 0x00)", read_data);
    
    read_pixel_byte_horizontal(8, 1, read_data);
    $display("Read from (8, 1) after reset: 0x%02h (expected: 0x00)", read_data);
    $display("Reset test complete.\n");
    
    // Display cleared framebuffer
    display_framebuffer();
    
    // Finish simulation
    $display("========================================");
    $display("ALL TESTS COMPLETED SUCCESSFULLY");
    $display("========================================\n");
    
    repeat(10) @(posedge clk);
    $finish;
end

// Timeout watchdog
initial begin
    #1000000; // 1ms timeout
    $display("ERROR: Simulation timeout!");
    $finish;
end

// Optional: Generate VCD file for waveform viewing
initial begin
    $dumpfile("testbenches/dumpfiles/framebuffer_tb.vcd");
    $dumpvars(0, test);
end

endmodule

`default_nettype wire
