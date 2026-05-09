`timescale 1ns/1ps

module hps_uart_bridge_top (
  input  wire        CLOCK_50,
  input  wire [3:0]  KEY,
  output wire [9:0]  LEDR,
  inout  wire [35:0] GPIO_0
);
  wire uart_txd;
  wire uart_rxd;
  reg [31:0] heartbeat;

  // Same external UART wiring as the standalone debug bitstream:
  // GPIO_0[0] -> USB-UART RX, GPIO_0[1] <- USB-UART TX.
  assign GPIO_0[0] = uart_txd;
  assign uart_rxd  = GPIO_0[1];
  assign GPIO_0[35:2] = {34{1'bz}};

  always @(posedge CLOCK_50 or negedge KEY[0]) begin
    if (!KEY[0])
      heartbeat <= 32'd0;
    else
      heartbeat <= heartbeat + 1'b1;
  end

  soc_system u_soc_system (
    .clk_clk  (CLOCK_50),
    .uart_txd (uart_txd),
    .uart_rxd (uart_rxd)
  );

  assign LEDR[0] = heartbeat[24];
  assign LEDR[1] = ~KEY[0];
  assign LEDR[2] = uart_txd;
  assign LEDR[3] = uart_rxd;
  assign LEDR[9:4] = 6'b0;
endmodule
