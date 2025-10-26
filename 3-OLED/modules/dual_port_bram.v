
`default_nettype none
module dual_port_bram #(
    parameter ADDR_WIDTH = 11,
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 1 << ADDR_WIDTH
)
(
    input wire clk,

    // Port A
    input wire we_a, // Active high write enable
    input wire [ADDR_WIDTH-1:0] addr_a,
    input wire [DATA_WIDTH-1:0] din_a,
    output reg [DATA_WIDTH-1:0] dout_a,

    // Port B
    input wire we_b, // Active high write enable
    input wire [ADDR_WIDTH-1:0] addr_b,
    input wire [DATA_WIDTH-1:0] din_b,
    output reg [DATA_WIDTH-1:0] dout_b
);

// Memory Declaration
reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Port A Operations
always @(posedge clk) begin
    if (we_a) begin
        mem[addr_a] <= din_a; // Write operation for Port A
    end
    dout_a <= mem[addr_a]; // Read operation for Port A
end

// Port B Operations
always @(posedge clk) begin
    if (we_b) begin
        mem[addr_b] <= din_b; // Write operation for Port B
    end
    dout_b <= mem[addr_b]; // Read operation for Port B
end 

endmodule
