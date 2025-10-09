`default_nettype none

module ssd1309_driver(
    input clk, // Module input clock. Assumes 27Mhz. SPI data will clock out at half this frequency
    input reset, // Active high - resets state machine and reinitializes the module
    output reg sclk, // OLED d0 pin (acts as SCLK for SPI)
    output reg sdin, // OLED d1 pin (acts as SDIN for SPI) - data is shifted in on rising edge of SCLK, and is MSB first
    output reg res, // OLED reset pin
    output reg cmd, // OLED command pin - Command == LOW, pixel data == HIGH
    output reg cs, // OLED chip select pin - pull low to communicate with module
    output reg [4:0] led_pin_o // For debugging - shows current state of operation state machine
);

initial begin
    sclk <= 0;
    sdin <= 0;
    res <= 1;
    cmd <= 0;
    cs <= 1;
end

parameter DISPLAY_WIDTH = 128;
parameter DISPLAY_HEIGHT = 64;
parameter STARTUP_DELAY = 10000000; // Delay to use after power has been applied before resetting the display (~1/3 second at 27Mhz) 
parameter FRAME_RATE = 100; // Target frame rate for refreshing the display
parameter FRAME_RATE_DELAY = 27000000 / FRAME_RATE; // Delay time between frames (27mhz clock)

// OLED Command Bytes
localparam CONTRAST = 8'h81; // Two byte command, second byte is contrast level 0-255
localparam ENTIRE_DISPLAY_ON = 8'hA5; // Sets the entire display to ON regardless of RAM contents
localparam ENTIRE_DISPLAY_RAM = 8'hA4; // Sets the entire display to RAM contents
localparam DISPLAY_MODE_ACTIVE_HIGH = 8'hA6; // Normal display mode
localparam DISPLAY_MODE_ACTIVE_LOW = 8'hA7; // Inverse display mode
localparam CHARGE_PUMP_CONFIG = 8'h8D; // Two byte command, second byte is 0x10 to disable charge pump, 0x14 to enable
    localparam ENABLE_CHARGE_PUMP = 8'h14; // Must enable charge pump before DISPLAY_ON
    localparam DISABLE_CHARGE_PUMP = 8'h10;
localparam DISPLAY_OFF = 8'hAE; // Display OFF (sleep mode)
localparam DISPLAY_ON = 8'hAF; // Display ON (normal mode)
localparam SET_MEMORY_ADDR_MODE = 8'h20; // Set memory addressing mode - two byte command followed by one of the next bytes
    localparam HORIZONTAL_ADDR_MODE = 8'h00; // Column pointer increments every byte, Page pointer will increment when reaching end of page (right)
    localparam VERTICAL_ADDR_MODE = 8'h01; // Page pointer will increment every byte, column pointer will increment when reaching bottom of display
    localparam PAGE_ADDR_MODE = 8'h02; // Default after reset - Column pointer increments every byte, page pointer does not increment (stays on page 0 after reaching end of display)

// Operation State Machine states
localparam STARTUP_PRE_RESET = 0;
localparam STARTUP_RESETTING = 1;
localparam STARTUP_POST_RESET = 2;
localparam INITIALIZING = 3;
localparam CLEAR_SCREEN = 4;
localparam DRAW_FRAMEBUFFER = 5;
localparam WRITE = 6; 
localparam IDLE = 7;

// Framebuffer register
//reg [DISPLAY_WIDTH-1:0] framebuffer [0:DISPLAY_HEIGHT-1];
reg [127:0] framebuffer [0:63]; // 128 bits wide (one row), 64 rows
// Initialize framebuffer to zeros
integer i;
initial begin
    // for (i = 0; i < 64; i = i + 1) begin
    //     framebuffer[i] = 128'h0;
    // end
    $readmemb("examples/horse_oled_128x64.bin", framebuffer);
    // framebuffer[0] = 128'h000000000000000000000000000000FF;
    // framebuffer[1] = 128'h0000000000000000000000000000FF00;
    // framebuffer[2] = 128'h00000000000000000000000000FF0000;
    // framebuffer[3] = 128'h000000000000000000000000FF000000;
    // framebuffer[4] = 128'h0000000000000000000000FF00000000;
    // framebuffer[5] = 128'h00000000000000000000FF0000000000;
    // framebuffer[6] = 128'h000000000000000000FF000000000000;
    // framebuffer[7] = 128'h0000000000000000FF00000000000000;
    // framebuffer[8] = 128'h00000000000000FF0000000000000000;
    // framebuffer[9] = 128'h000000000000FF000000000000000000;
    // framebuffer[10] = 128'h0000000000FF00000000000000000000;
    // framebuffer[11] = 128'h00000000FF0000000000000000000000;
    // framebuffer[12] = 128'h000000FF000000000000000000000000;
    // framebuffer[13] = 128'h0000FF00000000000000000000000000;
    // framebuffer[14] = 128'h00FF0000000000000000000000000000;
    // framebuffer[15] = 128'hFF000000000000000000000000000000;
    // framebuffer[16] = 128'h000000000000000000000000000000FF;
    // framebuffer[17] = 128'h0000000000000000000000000000FF00;
    // framebuffer[18] = 128'h00000000000000000000000000FF0000;
    // framebuffer[19] = 128'h000000000000000000000000FF000000;
    // framebuffer[20] = 128'h0000000000000000000000FF00000000;
    // framebuffer[21] = 128'h00000000000000000000FF0000000000;
    // framebuffer[22] = 128'h000000000000000000FF000000000000;
    // framebuffer[23] = 128'h0000000000000000FF00000000000000;
    // framebuffer[24] = 128'h00000000000000FF0000000000000000;
    // framebuffer[25] = 128'h000000000000FF000000000000000000;
    // framebuffer[26] = 128'h0000000000FF00000000000000000000;
    // framebuffer[27] = 128'h00000000FF0000000000000000000000;
    // framebuffer[28] = 128'h000000FF000000000000000000000000;
    // framebuffer[29] = 128'h0000FF00000000000000000000000000;
    // framebuffer[30] = 128'h00FF0000000000000000000000000000;
    // framebuffer[31] = 128'hFF000000000000000000000000000000;
    // framebuffer[32] = 128'h000000000000000000000000000000FF;
    // framebuffer[33] = 128'h0000000000000000000000000000FF00;
    // framebuffer[34] = 128'h00000000000000000000000000FF0000;
    // framebuffer[35] = 128'h000000000000000000000000FF000000;
    // framebuffer[36] = 128'h0000000000000000000000FF00000000;
    // framebuffer[37] = 128'h00000000000000000000FF0000000000;
    // framebuffer[38] = 128'h000000000000000000FF000000000000;
    // framebuffer[39] = 128'h0000000000000000FF00000000000000;
    // framebuffer[40] = 128'h00000000000000FF0000000000000000;
    // framebuffer[41] = 128'h000000000000FF000000000000000000;
    // framebuffer[42] = 128'h0000000000FF00000000000000000000;
    // framebuffer[43] = 128'h00000000FF0000000000000000000000;
    // framebuffer[44] = 128'h000000FF000000000000000000000000;
    // framebuffer[45] = 128'h0000FF00000000000000000000000000;
    // framebuffer[46] = 128'h00FF0000000000000000000000000000;
    // framebuffer[47] = 128'hFF000000000000000000000000000000;
    // framebuffer[48] = 128'h000000000000000000000000000000FF;
    // framebuffer[49] = 128'h0000000000000000000000000000FF00;
    // framebuffer[50] = 128'h00000000000000000000000000FF0000;
    // framebuffer[51] = 128'h000000000000000000000000FF000000;
    // framebuffer[52] = 128'h0000000000000000000000FF00000000;
    // framebuffer[53] = 128'h00000000000000000000FF0000000000;
    // framebuffer[54] = 128'h000000000000000000FF000000000000;
    // framebuffer[55] = 128'h0000000000000000FF00000000000000;
    // framebuffer[56] = 128'h00000000000000FF0000000000000000;
    // framebuffer[57] = 128'h000000000000FF000000000000000000;
    // framebuffer[58] = 128'h0000000000FF00000000000000000000;
    // framebuffer[59] = 128'h00000000FF0000000000000000000000;
    // framebuffer[60] = 128'h000000FF000000000000000000000000;
    // framebuffer[61] = 128'h0000FF00000000000000000000000000;
    // framebuffer[62] = 128'h00FF0000000000000000000000000000;
    // framebuffer[63] = 128'hFF000000000000000000000000000000;
end


// Operation State Machine registers
reg [4:0] operation_state = 0; // Current state of the operation state machine
// Startup state registers
reg [27:0] startup_delay_counter = 0; // 28 bits to count to 10,000,000 for startup delay
// Initialization state registers
reg [4:0] initialization_command_index = 0; // Index of the next initialization command to send
// Clear screen state registers
reg [11:0] clear_counter = 0; // Counter used to clear the screen
// Write state registers
reg [7:0] write_byte = 0; // Byte to send to OLED (either command or data)
reg [3:0] write_byte_bit_counter = 0; // Counts bits of the write_byte that have been sent
reg [5:0] write_clock_counter = 0; // Counter used to pulse SCLK
reg write_complete = 0; // Flag to signal if writing is complete
reg [4:0] return_state = 0; // State to return to after writing a byte
// Draw Framebuffer state registers
reg [31:0] frame_rate_counter = 0; // Counter to delay between drawing frames
reg [7:0] draw_column = 0; // Current column being drawn
reg [7:0] draw_page = 0; // Current page being drawn (8 pages for 64 pixel height)
reg [7:0] draw_row = 0; // Current row being drawn
reg frame_complete = 0; // Flag to designate if a full frame has completed writing



// Debug Registers and Assignments

//assign led_pin_o[4] = ~sclk; // For debugging - show when a write is complete
reg [23:0] debug_write_byte = 0;

// Debug - every second increment the data in the framebuffer
// reg [31:0] debug_framebuffer_counter = 0;
// always @(posedge clk) begin
//     led_pin_o[5:0] = ~draw_page; // For debugging - show current state on LEDs
//     debug_framebuffer_counter <= debug_framebuffer_counter + 1;
//     if(debug_framebuffer_counter >= 27000000 / 1000) begin // Every second
//         framebuffer[0] <= framebuffer[0] + 1; // Increment first row of framebuffer
//         debug_framebuffer_counter <= 0;
//     end
// end




// Operation state machine
always @(posedge clk) begin

    // If reset is asserted, go back to initial state
    if(reset) begin
        operation_state <= STARTUP_PRE_RESET;
        startup_delay_counter <= 0;
        initialization_command_index <= 0;
        write_byte <= 0;
        write_byte_bit_counter <= 0;
        write_clock_counter <= 0;
        write_complete <= 0;
        return_state <= 0;
    end


    case (operation_state)
        // PRE_RESET: Wait for some time after power is applied before resetting the display
        STARTUP_PRE_RESET: begin
            cs <= 1; // Deselect the OLED
            res <= 1; // Not yet resetting
            startup_delay_counter <= startup_delay_counter + 1; 
            if(startup_delay_counter >= STARTUP_DELAY) begin
                startup_delay_counter <= 0;
                operation_state <= STARTUP_RESETTING;
            end
        end

        // RESETTING: Assert reset for some time
        STARTUP_RESETTING: begin
            cs <= 1; // Deselect the OLED
            res <= 0; // Assert reset
            startup_delay_counter <= startup_delay_counter + 1; 
            if(startup_delay_counter >= STARTUP_DELAY) begin // Hold reset low for STARTUP_DELAY clock cycles
                startup_delay_counter <= 0;
                operation_state <= STARTUP_POST_RESET;
            end
        end

        // POST_RESET: Deassert reset and wait for some time before starting initialization
        STARTUP_POST_RESET: begin
            cs <= 1; // Deselect the OLED
            res <= 1; // Deassert reset
            startup_delay_counter <= startup_delay_counter + 1; 
            if(startup_delay_counter >= STARTUP_DELAY) begin // Wait some time after deasserting reset
                startup_delay_counter <= 0;
                operation_state <= INITIALIZING;
            end
        end

        // INITIALIZING: Send initialization commands to the OLED
        INITIALIZING: begin
            // Load the next command to send
            case (initialization_command_index)
                0: begin write_byte <= DISPLAY_OFF; end
                1: begin write_byte <= SET_MEMORY_ADDR_MODE; end
                2: begin write_byte <= HORIZONTAL_ADDR_MODE; end
                3: begin write_byte <= CONTRAST; end
                4: begin write_byte <= 8'h7F; end // Contrast level
                5: begin write_byte <= DISPLAY_MODE_ACTIVE_HIGH; end
                6: begin write_byte <= ENTIRE_DISPLAY_RAM; end
                7: begin write_byte <= CHARGE_PUMP_CONFIG; end
                8: begin write_byte <= ENABLE_CHARGE_PUMP; end
                9: begin write_byte <= DISPLAY_ON; end
                default: begin write_byte <= 8'h00; end // No operation
            endcase
            // Go to WRITE state to send the command
            if(initialization_command_index <= 9) begin
                cmd <= 0; // Command mode
                return_state <= INITIALIZING; // After writing command, return to INITIALIZING state
                operation_state <= WRITE; // Go to WRITE state to send the command
                initialization_command_index <= initialization_command_index + 1; // Move to next command
            end
            else begin
                operation_state <= CLEAR_SCREEN; // All initialization commands sent, move to CLEAR_SCREEN state
                clear_counter <= 0;
            end
        end

        // CLEAR_SCREEN: Clear the display by writing zeros to the entire framebuffer
        CLEAR_SCREEN: begin
            if(clear_counter < DISPLAY_WIDTH * DISPLAY_HEIGHT / 8) begin
                write_byte <= 8'h00; // Byte of zeros to clear the screen
                cmd <= 1; // Data mode
                return_state <= CLEAR_SCREEN; // After writing byte, return to CLEAR_SCREEN state
                operation_state <= WRITE; // Go to WRITE state to send the byte
                clear_counter <= clear_counter + 1; // Increment clear counter
            end
            else begin
                clear_counter <= 0;
                operation_state <= DRAW_FRAMEBUFFER;
            end
        end

        // DRAW_FRAMEBUFFER: Write the contents of the framebuffer to the display
        DRAW_FRAMEBUFFER: begin
            if (draw_column >= 127) begin // Rollover at 127 columns
                if(draw_page >= 7) begin // If we are at the final (bottom) page, delay to achieve frame_rate, then loop back to top-left
                    frame_complete <= 1;
                    frame_rate_counter <= frame_rate_counter + 1;
                    if(frame_rate_counter >= FRAME_RATE_DELAY) begin // Wait for frame rate time
                        frame_complete <= 0;
                        frame_rate_counter <= 0;
                        draw_column <= 0;
                        draw_page <= 0;
                    end
                end
                else begin // Otherwise increment the page
                    draw_column <= 0;
                    draw_page <= draw_page + 1;
                end
            end
            else begin
                draw_column <= draw_column + 1;
            end

            if(!frame_complete) begin
                // Wire up the framebuffer to the write byte
                draw_row <= draw_page * 8;
                write_byte <= {
                    framebuffer[(draw_page * 8) + 7][draw_column],
                    framebuffer[(draw_page * 8) + 6][draw_column],
                    framebuffer[(draw_page * 8) + 5][draw_column],
                    framebuffer[(draw_page * 8) + 4][draw_column],
                    framebuffer[(draw_page * 8) + 3][draw_column],
                    framebuffer[(draw_page * 8) + 2][draw_column],
                    framebuffer[(draw_page * 8) + 1][draw_column],
                    framebuffer[(draw_page * 8) + 0][draw_column]
                };

                // Write the data
                cmd <= 1; // Data mode
                return_state <= DRAW_FRAMEBUFFER;
                operation_state <= WRITE;
            end
        end


        // WRITE: Send a byte to the OLED - assumes cmd/data mode has been set appropriately before entering this state
        WRITE: begin
            cs <= 0; // Select the OLED
            write_clock_counter <= write_clock_counter + 1; // Increment the clock counter

            // On even clock counter and write not complete, store the appropriate bit in our data out register and lower the clock
            if(write_clock_counter % 2 == 0 && !write_complete) begin
                sdin <= write_byte[7 - write_byte_bit_counter]; // Send MSB first
                sclk <= 0;
            end
            // On odd and write not complete - we raise the clock, increment the bit counter, and check if writing is finished
            if(write_clock_counter % 2 == 1 && !write_complete) begin
                sclk <= 1;
                write_byte_bit_counter <= write_byte_bit_counter + 1; // Increment bit counter
                if(write_byte_bit_counter >= 7) begin
                    write_complete <= 1; // Writing is finished
                end
            end
            // If writing is complete, reset counters and return to the previous state
            if(write_complete) begin
                cs <= 1; // Deselect the OLED
                write_complete <= 0;
                write_byte <= 0;
                write_byte_bit_counter <= 0;
                write_clock_counter <= 0;
                operation_state <= return_state; // Return to the previous state
            end
        end

        // IDLE: Wait here until further instructions (for simulation, we will write a byte of data every second)
        IDLE: begin
            startup_delay_counter <= startup_delay_counter + 1; 
            if(startup_delay_counter >= 439) begin
                startup_delay_counter <= 0;
                write_byte <= debug_write_byte/30; 
                debug_write_byte <= debug_write_byte + 1; // Increment the byte to write next time
                cmd <= 1; // Data mode
                return_state <= IDLE;
                operation_state <= WRITE;
            end
        end

    endcase
end

endmodule