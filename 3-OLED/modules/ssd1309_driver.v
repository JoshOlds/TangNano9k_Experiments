`default_nettype none

// TODO: test reading from framebuffer module - update the draw_framebuffer state to read from the framebuffer module instead of internal memory
// TODO: Can we make a framebuffer test bench?
// TODO: Clear screen should reset the framebuffer

module ssd1309_driver(
    input clk, // Module input clock. Assumes 27Mhz. SPI data will clock out at half this frequency
    input reset, // Active high - resets state machine and reinitializes the module
    output reg sclk, // OLED d0 pin (acts as SCLK for SPI)
    output reg sdin, // OLED d1 pin (acts as SDIN for SPI) - data is shifted in on rising edge of SCLK, and is MSB first
    output reg res, // OLED reset pin
    output reg cmd, // OLED command pin - Command == LOW, pixel data == HIGH
    output reg cs, // OLED chip select pin - pull low to communicate with module
    output reg [3:0] led_pin_o, // For debugging - shows current state of operation state machine

    // Framebuffer interface
    input [7:0] fb_dout, // Framebuffer read data output (8 pixels, 1 bit each)
    input fb_data_valid, // Framebuffer read data valid signal
    input fb_busy, // Framebuffer busy signal
    output reg [7:0] fb_r_xpos, // Framebuffer read x position
    output reg [7:0] fb_r_ypos, // Framebuffer read y position
    output reg fb_r_mode, // Framebuffer read mode (0: horizontal read, 1: column read)
    output reg fb_re // Framebuffer read enable (active high)
);

assign led_pin_o = ~operation_state[3:0]; // Output current operation state for debugging

initial begin
    sclk <= 0;
    sdin <= 0;
    res <= 1;
    cmd <= 0;
    cs <= 1;

    // Framebuffer interface
    fb_r_xpos <= 0;
    fb_r_ypos <= 0;
    fb_r_mode <= 0; // Default to horizontal read mode
    fb_re <= 0;
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
localparam WAITING_FOR_FRAMERATE = 7; // New state for frame rate delay
localparam IDLE = 8; 


// Operation State Machine registers
reg [4:0] operation_state = 0; // Current state of the operation state machine
// Startup state registers
reg [27:0] startup_delay_counter = 0; // 28 bits to count to 10,000,000 for startup delay
// Initialization state registers
reg [4:0] initialization_command_index = 0; // Index of the next initialization command to send
// Clear screen state registers
reg [11:0] clear_counter = 0; // Counter used to clear the screen

//Read pipeline registers
reg [7:0] read_pipeline_counter = 0; // Counter used to pipeline read from framebuffer
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
reg frame_complete = 0; // Flag to designate if a full frame has completed writing
reg waiting_for_data = 0; // Flag to wait for framebuffer data to be valid
reg ready_to_increment = 0; // Flag to increment draw_column after writing


// Operation state machine
always @(posedge clk) begin

    // If reset is asserted, go back to initial state
    if(reset) begin
        operation_state <= STARTUP_PRE_RESET;
        startup_delay_counter <= 0;
        initialization_command_index <= 0;
        clear_counter <= 0;
        write_byte <= 0;
        write_byte_bit_counter <= 0;
        write_clock_counter <= 0;
        write_complete <= 0;
        return_state <= 0;
        frame_rate_counter <= 0;
        draw_column <= 0;
        draw_page <= 0;
        frame_complete <= 0;
        waiting_for_data <= 0;
        ready_to_increment <= 0;
        read_pipeline_counter <= 0;
        fb_re <= 0;
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
                5: begin write_byte <= DISPLAY_MODE_ACTIVE_LOW; end
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
            // if(clear_counter < DISPLAY_WIDTH * DISPLAY_HEIGHT / 8) begin
            //     write_byte <= 8'h00; // Byte of zeros to clear the screen
            //     cmd <= 1; // Data mode
            //     return_state <= CLEAR_SCREEN; // After writing byte, return to CLEAR_SCREEN state
            //     operation_state <= WRITE; // Go to WRITE state to send the byte
            //     clear_counter <= clear_counter + 1; // Increment clear counter
            // end
            // else begin
            //     clear_counter <= 0;
            //     operation_state <= DRAW_FRAMEBUFFER;
            // end
            operation_state <= DRAW_FRAMEBUFFER;
        end

        // DRAW_FRAMEBUFFER: Write the contents of the framebuffer to the display
        DRAW_FRAMEBUFFER: begin
            // Increment col/page address after writing (happens after below READ logic)
            if (ready_to_increment) begin
                ready_to_increment <= 0;
                // Increment draw_column after writing
                if (draw_column >= 127) begin 
                    if (draw_page >= 7) begin 
                        // All pages complete
                        operation_state <= WAITING_FOR_FRAMERATE;
                        frame_complete <= 1;
                        fb_re <= 0;
                    end else begin
                        // Reached the end of the row, move to next page
                        draw_column <= 0;
                        draw_page <= draw_page + 1;
                    end
                end else begin
                    // Not at the end of the row, increment column
                    draw_column <= draw_column + 1;
                end
            end

            // READ logic for reading from framebuffer
            if(!frame_complete) begin
                case (read_pipeline_counter)
                    0: begin
                        // Start the read process
                        read_pipeline_counter <= 1;
                        fb_r_mode <= 1; // COLUMN read mode
                        fb_r_xpos <= draw_column;
                        fb_r_ypos <= draw_page * 8;
                    end
                    1: begin
                        // Delay the enable of read to allow for xpos and ypos to propagate
                        read_pipeline_counter <= 2;
                        fb_re <= 1; // Enable read
                    end
                    2: begin
                        // wait until data is valid
                        if(fb_data_valid) begin
                            // Data is now valid, capture it and prepare to write
                            write_byte <= fb_dout;
                            fb_re <= 0; // Disable read (which will clear fb_data_valid)
                            // Transition to WRITE state to send the data byte
                            cmd <= 1; // Data mode
                            return_state <= DRAW_FRAMEBUFFER;
                            operation_state <= WRITE;
                            ready_to_increment <= 1; // Set flag to increment after writing
                            read_pipeline_counter <= 0; // Reset pipeline counter for next read
                        end
                    end
                    default: begin
                        read_pipeline_counter <= 0;
                    end
                endcase
            end
        end

        // WAITING_FOR_FRAMERATE: Wait for the frame rate delay before starting the next frame
        WAITING_FOR_FRAMERATE: begin
            frame_rate_counter <= frame_rate_counter + 1;
            if(frame_rate_counter >= FRAME_RATE_DELAY) begin
                frame_rate_counter <= 0;
                draw_column <= 0;
                draw_page <= 0;
                frame_complete <= 0;
                operation_state <= DRAW_FRAMEBUFFER;
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

        
        IDLE: begin
        
        end

    endcase
end

endmodule