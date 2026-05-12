// MMIO «DMA»-заготовка: четыре программируемых слова; rdata — комбинационное чтение.
`timescale 1ns/1ps
module uart_16550_dma_port (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        we,
  input  wire [1:0]  addr,
  input  wire [31:0] wdata,
  output reg  [31:0] rdata
);

  reg [31:0] tx_desc_lo;
  reg [31:0] tx_desc_hi;
  reg [31:0] rx_desc_lo;
  reg [31:0] rx_desc_hi;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_desc_lo <= 32'd0;
      tx_desc_hi <= 32'd0;
      rx_desc_lo <= 32'd0;
      rx_desc_hi <= 32'd0;
    end else if (we) begin
      case (addr)
        2'b00: tx_desc_lo <= wdata;
        2'b01: tx_desc_hi <= wdata;
        2'b10: rx_desc_lo <= wdata;
        2'b11: rx_desc_hi <= wdata;
      endcase
    end
  end

  always @* begin
    case (addr)
      2'b00:   rdata = tx_desc_lo;
      2'b01:   rdata = tx_desc_hi;
      2'b10:   rdata = rx_desc_lo;
      default: rdata = rx_desc_hi;
    endcase
  end
endmodule
