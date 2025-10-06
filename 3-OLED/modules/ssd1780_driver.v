`default_nettype none

module ssd1780_driver(
    input clk, // Module input clock. SPI data will clock out at half this frequency
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

// OLED Command Bytes
localparam CONTRAST = 8'h81; // Two byte command, second byte is contrast level 0-255
localparam ENTIRE_DISPLAY_ON = 8'hA4; // Sets the entire display to ON regardless of RAM contents
localparam ENTIRE_DISPLAY_RAM = 8'hA5; // Sets the entire display to RAM contents
localparam DISPLAY_MODE_ACTIVE_HIGH = 8'hA6; // Normal display mode
localparam DISPLAY_MODE_ACTIVE_LOW = 8'hA7; // Inverse display mode
localparam DISPLAY_OFF = 8'hAE; // Display OFF (sleep mode)
localparam DISPLAY_ON = 8'hAF; // Display ON (normal mode)
localparam SET_MEMORY_ADDR_MODE = 8'h20; // Set memory addressing mode - two byte command followed by one of the next bytes
    localparam HORIZONTAL_ADDR_MODE = 8'h00; // Column pointer increments every byte, Page pointer will increment when reaching end of page (right)
    localparam VERTICAL_ADDR_MODE = 8'h01; // Page pointer will increment every byte, column pointer will increment when reaching bottom of display
    localparam PAGE_ADDR_MODE = 8'h02; // Default after reset - Column pointer increments every byte, page pointer does not increment (stays on page 0 after reaching end of display)

// Framebuffer register
reg [DISPLAY_WIDTH-1:0] framebuffer [0:DISPLAY_HEIGHT-1];

// Operation State Machine registers
reg [27:0] startup_delay_counter = 0; // 28 bits to count to 10,000,000 for startup delay
reg [4:0] operation_state = 0; // Current state of the operation state machine
reg [4:0] initialization_command_index = 0; // Index of the next initialization command to send
reg [7:0] write_byte = 0; // Byte to send to OLED (either command or data)
reg [3:0] write_byte_bit_counter = 0; // Counts bits of the write_byte that have been sent
reg [5:0] write_clock_counter = 0; // Counter used to pulse SCLK
reg write_complete = 0; // Flag to signal if writing is complete
reg [4:0] return_state = 0; // State to return to after writing a byte

assign led_pin_o[3:0] = ~operation_state; // For debugging - show current state on LEDs
assign led_pin_o[4] = ~sclk; // For debugging - show when a write is complete

// Operation State Machine states
localparam STARTUP_PRE_RESET = 0;
localparam STARTUP_RESETTING = 1;
localparam STARTUP_POST_RESET = 2;
localparam INITIALIZING = 3;
localparam WRITE = 4;
localparam WRITE_DATA = 5;  
localparam IDLE = 6;


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
                5: begin write_byte <= DISPLAY_MODE_ACTIVE_LOW; end
                6: begin write_byte <= ENTIRE_DISPLAY_RAM; end
                7: begin write_byte <= DISPLAY_ON; end
                8: begin write_byte <= ENTIRE_DISPLAY_ON; end
                default: begin write_byte <= 8'h00; end // No operation
            endcase
            // Go to WRITE state to send the command
            if(initialization_command_index <= 8) begin
                cmd <= 0; // Command mode
                return_state <= INITIALIZING; // After writing command, return to INITIALIZING state
                operation_state <= WRITE; // Go to WRITE state to send the command
                initialization_command_index <= initialization_command_index + 1; // Move to next command
            end
            else begin
                operation_state <= IDLE;
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

        //IDLE: In IDLE state, flash the screen on and off by toggling the display mode every second
        IDLE: begin
            // For simulation purposes, we will toggle every 27,000,000 clock cycles (1s at 27MHz)
            startup_delay_counter <= startup_delay_counter + 1; 
            if(startup_delay_counter >= STARTUP_DELAY) begin
                startup_delay_counter <= 0;

                // write a byte of data (0xFF) to the display to turn a page of pixels on
                write_byte <= 8'hFF;
                cmd <= 1; // Data mode
                return_state <= IDLE;
                operation_state <= WRITE;
            end
        end

    endcase
end



integer i;
always @(posedge clk) begin
    // Set all bits in framebuffer to 1
    for(i=0; i<DISPLAY_HEIGHT; i=i+1) begin
        framebuffer[i] = {DISPLAY_WIDTH{1'b1}};
    end
end

endmodule