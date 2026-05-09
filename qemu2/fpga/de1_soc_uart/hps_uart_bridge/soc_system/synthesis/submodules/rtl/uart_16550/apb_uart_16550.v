// APB3 (без wait): pready=1 с фазой доступа, prdata = {24'h0, rdata8}.
// Для AXI4-Lite: те же смещения по байтам 0x00..0x1C (paddr[4:2] = номер регистра 0..7).
`timescale 1ns/1ps
module apb_uart_16550 #(
  parameter PADDR_W = 8
) (
  input  wire                 pclk, presetn,
  input  wire                 psel, penable, pwrite,
  input  wire [PADDR_W-1:0]  paddr,
  input  wire [31:0]         pwdata,
  input  wire [3:0]          pstrb,
  output wire [31:0]        prdata,
  output wire                pready,
  output wire                pslverr,
  output wire                uart_txd, input wire uart_rxd, output wire uart_irq
);
  // Word index: 0..7  => registers @ 0x00..0x1C; 8..11 => demo ext @ 0x20..0x2C
  wire [5:0] widx  = paddr[7:2];
  wire        core  = widx < 6'd8;
  wire  we  = psel & penable & pwrite  & pstrb[0] & core;
  wire  re  = psel & penable & ~pwrite  & core;
  wire [2:0] adr  = widx[2:0];
  wire [7:0] rd;
  wire [31:0] rdata32;
  uart_16550_core u (
    .clk(pclk), .rst_n(presetn), .rxd_in(uart_rxd), .txd_out(uart_txd), .intr(uart_irq),
    .reg_adr(adr), .widx(widx), .reg_we(we), .reg_re(re), .wdata8(pwdata[7:0]),
    .rdata8(rd), .rdata32(rdata32)
  );
  assign prdata  = rdata32;
  assign pready  = psel & penable;
  assign pslverr  = 1'b0;
endmodule
