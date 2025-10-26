
`default_nettype none
module single_port_bram #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 1 << ADDR_WIDTH
)
(
    input wire clk,
    input wire we, // Active high write enable
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] din,
    output reg [DATA_WIDTH-1:0] dout
);

// Memory Declaration

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Synchronous Write
always @(posedge clk) begin
    if (we) begin
        mem[addr] <= din; // Write operation
    end
    else begin
        dout <= mem[addr]; // Read operation
    end
end

endmodule
