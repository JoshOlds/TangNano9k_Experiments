`timescale 1ns/1ps
`default_nettype none

// Testbench for ssd1780_driver
module test;

    // Clock generation
    reg clk = 1'b0;
    localparam real CLK_PERIOD_NS = 10.0; // 100 MHz for fast sim
    always #(CLK_PERIOD_NS/2.0) clk = ~clk;

    // DUT I/Os
    wire sclk;
    wire reset;
    wire sdin;
    wire res;
    wire cmd;
    wire cs;

    // Instantiate DUT with reduced startup delay for simulation speed
    ssd1780_driver #(
        .STARTUP_DELAY(10) // keep small for quick simulation
    ) dut (
        .clk(clk),
        .reset(1'b0), // No reset for testbench
        .sclk(sclk),
        .sdin(sdin),
        .res(res),
        .cmd(cmd),
        .cs(cs)
    );

initial begin
    #400000 $finish;
end

initial begin
  $dumpfile("testbenches/dumpfiles/oled_tb.vcd");
  $dumpvars(0, test);
end

endmodule

`default_nettype wire