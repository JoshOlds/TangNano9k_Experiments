module test();
  reg clk = 0;
  reg uart_rx = 1;
  wire uart_tx;

  wire [7:0] uart_rx_data;
  wire uart_rx_byte_ready;
  wire uart_tx_ready;
  reg [7:0] uart_tx_data;
  reg uart_tx_trigger;

  uart u(
    .clk_i(clk),
    .uart_rx_i(uart_rx),
    .rx_byte_ready_o(uart_rx_byte_ready),
    .rx_data_o(uart_rx_data),
    .uart_tx_o(uart_tx),
    .tx_data_i(uart_tx_data),
    .tx_trigger_i(uart_tx_trigger),
    .tx_complete_o(uart_tx_ready)
  );

  reg uart_byte_read = 0;
  always @(posedge clk) begin
    if(uart_rx_byte_ready && !uart_byte_read) begin
      uart_byte_read <= 1;
      $display("Received byte: %b", uart_rx_data);
  end
    if(!uart_rx_byte_ready) begin
      uart_byte_read <= 0;
    end
  end

    //Loopback UART for testing
    reg tx_loopback_sent_already = 0; // To avoid multiple triggers for the same byte in loopback mode
    
    always @(posedge clk) begin
        uart_tx_trigger <= 0; // Default to no trigger
        if(!tx_loopback_sent_already && uart_rx_byte_ready && uart_tx_ready) begin
            uart_tx_data <= uart_rx_data; // Load the data to be sent with the last received byte
            tx_loopback_sent_already <= 1;
            uart_tx_trigger <= 1; // Trigger the TX to send the byte
        end
        if(!uart_rx_byte_ready) begin
            tx_loopback_sent_already <= 0;
        end
    end

always
  #1  clk = ~clk;

initial begin
  $display("Starting UART RX");


  #468 uart_rx=0;
  #468 uart_rx=1;
  #468 uart_rx=0;
  #468 uart_rx=1;
  #468 uart_rx=0;
  #468 uart_rx=1;
  #468 uart_rx=0;
  #468 uart_rx=1;
  #468 uart_rx=0;
  #468 uart_rx=1;

  
  for (integer i = 0; i < 50; i = i + 1) begin
    #468 uart_rx=0;
    #468 uart_rx=1;
    #468 uart_rx=0;
    #468 uart_rx=1;
    #468 uart_rx=0;
    #468 uart_rx=1;
    #468 uart_rx=0;
    #468 uart_rx=1;
    #468 uart_rx=0;
    #468 uart_rx=1;
  end

  #20000 $finish;
end

initial begin
  $dumpfile("uart.vcd");
  $dumpvars(0,test);
end

endmodule

