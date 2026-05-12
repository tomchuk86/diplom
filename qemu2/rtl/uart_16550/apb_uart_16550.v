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
  // Word index: 0..7 regs; 8..11 demo; 12..13 scratch; 14..15 ID; 16..19 DMA; 20..39 mmio bucket.
  wire [5:0] widx  = paddr[7:2];
  wire        acc_ok = widx <= 6'd39;
  wire        core  = widx < 6'd8;
  wire        demo_ext = (widx >= 6'd8) & (widx <= 6'd11);
  wire        scratch_ext = (widx == 6'd12) | (widx == 6'd13);
  wire        dma_ext = (widx >= 6'd16) & (widx <= 6'd19);
  wire        bucket_ext = (widx >= 6'd20) & (widx <= 6'd39);
  wire        ext   = demo_ext | scratch_ext | dma_ext | bucket_ext;
  wire        we_ok = core ? pstrb[0]
                          : (scratch_ext | dma_ext | bucket_ext) ? (|pstrb) : pstrb[0];
  wire  we  = psel & penable & pwrite  & we_ok & (core | ext) & acc_ok;
  wire  re  = psel & penable & ~pwrite  & core & acc_ok;
  wire [2:0] adr  = widx[2:0];
  wire [7:0] rd;
  wire [31:0] rdata32;
  uart_16550_core u (
    .clk(pclk), .rst_n(presetn), .rxd_in(uart_rxd), .txd_out(uart_txd), .intr(uart_irq),
    .reg_adr(adr), .widx(widx), .reg_we(we), .reg_re(re),
    .wdata8(pwdata[7:0]), .wdata32(pwdata),
    .rdata8(rd), .rdata32(rdata32)
  );
  assign prdata  = acc_ok ? rdata32 : 32'd0;
  assign pready  = psel & penable;
  assign pslverr = psel & penable & ~acc_ok;
endmodule
