module top
(
    input clk,
    input btn1,
    input btn2,
    output [5:0] led
);

localparam WAIT_TIME = 13500000;
reg [5:0] ledCounter = 0;
reg [7:0] clockMultiplier = 1;
reg [23:0] clockCounter = 0;
reg btn1_last = 1;
reg btn2_last = 1;

always @(posedge clk) begin
    // Counter
    clockCounter <= clockCounter + 1;
    if (clockCounter == (WAIT_TIME / clockMultiplier)) begin
        clockCounter <= 0;
        ledCounter <= ledCounter + 1;
    end

    // Buttons are active low
    // If button1 is pressed and was not pressed last time, increase multiplier
    if(btn1 == 0) begin
        if(btn1_last == 1) begin
            if(clockMultiplier < 64) begin
                clockMultiplier <= clockMultiplier * 2;
                clockCounter <= 0;
            end
        end
        btn1_last <= 0;
    end else begin
        btn1_last <= 1;
    end

    // If button2 is pressed and was not pressed last time, decrease multiplier
    if(btn2 == 0) begin
        if(btn2_last == 1) begin
            if(clockMultiplier > 1) begin
                clockMultiplier <= clockMultiplier / 2;
                clockCounter <= 0;
            end
        end
        btn2_last <= 0;
    end else begin
        btn2_last <= 1;
    end

end

assign led = ~ledCounter;

endmodule