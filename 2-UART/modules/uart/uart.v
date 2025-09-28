// UART module for sending and receiving serial data
// Configurable for different baud rates via the DELAY_FRAMES parameter

module uart
#(
    //parameter DELAY_FRAMES = 234 // 27,000,000 (27MHz) / 115200 Baud rate
    parameter DELAY_FRAMES = 27 // 27,000,000 (27MHz) / 1000000 Baud rate
)

(
    // Clock input: system clock that drives RX/TX state machines
    input wire clk_i,
    // UART RX input: asynchronous serial data input (idle = 1). Sampled by RX state machine.
    input wire uart_rx_i,
    // RX byte ready: asserted when rx_data_o contains a new complete byte
    output reg rx_byte_ready_o,
    // RX data: 8-bit received data (LSB first as received over UART)
    output reg [7:0] rx_data_o,

    // UART TX output: serial data output (idle = 1). Driven by TX state machine.
    output wire uart_tx_o,
    // TX data: 8-bit data to be transmitted when tx_trigger_i is asserted
    input wire [7:0] tx_data_i,
    // TX trigger: pulse (high for >=1 clk) indicating tx_data_i should be sent. 
    input wire tx_trigger_i,
    // Indicates when TX is idle and ready for new data
    output reg tx_complete_o = 1, 

    // Debug output: current state of the RX state machine (for debugging purposes)
    output reg [3:0] rx_state_debug
    
);

localparam HALF_DELAY_WAIT = (DELAY_FRAMES / 2); // We want to read the data from RX at the middle of the pulse. Do this by waiting a half clock before sampling.

// RX Registers
reg [3:0] rxState = 0;  // State machine for RX
reg [12:0] rxCounter = 0; // Counter for RX timing (count up to DELAY_FRAMES)
reg [2:0] rxBitNumber = 0; // Which bit are we receiving right now (0-7)

// RX State machine states
localparam RX_STATE_IDLE = 0;
localparam RX_STATE_START_BIT = 1;
localparam RX_STATE_READ_WAIT = 2;
localparam RX_STATE_READ = 3;
localparam RX_STATE_STOP_BIT = 4;

// RX State Machine
always @(posedge clk_i) begin
    rx_state_debug <= rxState;
    case (rxState)

        RX_STATE_IDLE: begin
            rx_byte_ready_o <= 0;
            if(uart_rx_i == 0) begin // Start bit detected
                rxState <= RX_STATE_START_BIT;
                rxCounter <= 1;
                rxBitNumber <= 0;
                rx_data_o <= 0; // Clear out old data
            end
        end

        RX_STATE_START_BIT: begin
            if(rxCounter >= HALF_DELAY_WAIT) begin
                rxState <= RX_STATE_READ_WAIT;
                rxCounter <= 1;
            end else
                rxCounter <= rxCounter + 1;
        end

        RX_STATE_READ_WAIT: begin
            rxCounter <= rxCounter + 1;
            if(rxCounter >= DELAY_FRAMES) begin
                rxState <= RX_STATE_READ;
                rxCounter <= 1;
            end
        end

        RX_STATE_READ: begin
            rx_data_o[rxBitNumber] <= uart_rx_i;
            if(rxBitNumber >= 7) begin
                rxState <= RX_STATE_STOP_BIT;
                rx_byte_ready_o <= 1;
            end
            else begin
                rxState <= RX_STATE_READ_WAIT;
                rxBitNumber <= rxBitNumber + 1;
                rxCounter <= rxCounter + 1;
            end
        end

        RX_STATE_STOP_BIT: begin
            // Wait for RX to go high again (stop bit)
            if(uart_rx_i == 1) begin
                rxState <= RX_STATE_IDLE;
            end
        end  
    endcase  
end


// TX Registers
reg [3:0] txState = 0;  // State machine for TX
reg [12:0] txCounter; // Counter for TX timing (count up to DELAY_FRAMES)
reg [2:0] txBitNumber; // Which bit are we sending right now (0-7)
reg txPinRegister = 1; // Register to drive TX Wire

// TX Port Assignments
assign uart_tx_o = txPinRegister;

// TX State machine states
localparam TX_STATE_IDLE = 0;
localparam TX_STATE_START_BIT = 1;
localparam TX_STATE_SEND = 2;
localparam TX_STATE_STOP_BIT = 3;

always @(posedge clk_i) begin

    case (txState)

        TX_STATE_IDLE: begin
            if(tx_trigger_i) begin 
                txState <= TX_STATE_START_BIT;
                txPinRegister <= 0; // Write the start bit (low)
                txCounter <=1; // Count the current clock cycle
                txBitNumber <= 0;
                tx_complete_o <= 0;
            end
        end

        TX_STATE_START_BIT: begin
            if(txCounter >= DELAY_FRAMES) begin
                txState <= TX_STATE_SEND;
                txCounter <= 1;
            end else
                txCounter <= txCounter + 1;
        end

        TX_STATE_SEND: begin
            txPinRegister <= tx_data_i[txBitNumber]; // Send the current bit
            if(txCounter >= DELAY_FRAMES) begin
                if(txBitNumber >= 7) begin // Stop on last bit
                    txState <= TX_STATE_STOP_BIT;
                    txPinRegister <= 1; // Stop bit is high
                    txCounter <= 1; 
                end else begin
                    txBitNumber <= txBitNumber + 1;
                    txCounter <= 1;
                end
            end else
                txCounter <= txCounter + 1;
        end

        TX_STATE_STOP_BIT: begin
            if(txCounter >= DELAY_FRAMES) begin
                txState <= TX_STATE_IDLE;
                txPinRegister <= 1; // Set TX back to idle (high)
                tx_complete_o <= 1;
            end else
                txCounter <= txCounter + 1;
        end
    endcase  
end
    

endmodule