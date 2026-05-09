// Avalon-MM slave wrapper for the APB UART16550 block.
//
// Use this module as a Platform Designer custom component when connecting the
// UART to the DE1-SoC HPS lightweight HPS-to-FPGA bridge. It presents a simple
// zero-wait Avalon-MM slave and translates accesses to the APB wrapper.
//
// Addressing:
//   Avalon word address 0  -> APB byte offset 0x00 (RBR/THR/DLL)
//   Avalon word address 1  -> APB byte offset 0x04 (IER/DLM)
//   ...
//   Avalon word address 7  -> APB byte offset 0x1C (SCR)
//   Avalon word address 8  -> APB byte offset 0x20 (TX_COUNT)
//   Avalon word address 9  -> APB byte offset 0x24 (RX_COUNT)
//   Avalon word address 10 -> APB byte offset 0x28 (ERR_COUNT)
//   Avalon word address 11 -> APB byte offset 0x2C (IRQ_COUNT)
`timescale 1ns/1ps

module avalon_apb_uart_16550 #(
  parameter ADDR_W = 6
) (
  input  wire                clk,
  input  wire                reset_n,

  input  wire [ADDR_W-1:0]   avs_address,
  input  wire                avs_read,
  input  wire                avs_write,
  input  wire [31:0]         avs_writedata,
  input  wire [3:0]          avs_byteenable,
  output wire [31:0]         avs_readdata,
  output wire                avs_waitrequest,

  output wire                irq,
  output wire                uart_txd,
  input  wire                uart_rxd
);
  wire        apb_access = avs_read | avs_write;
  wire [7:0]  apb_paddr  = {avs_address, 2'b00};
  wire [31:0] apb_prdata;
  wire        apb_pready;
  wire        apb_pslverr;

  apb_uart_16550 #(
    .PADDR_W(8)
  ) u_uart (
    .pclk(clk),
    .presetn(reset_n),
    .psel(apb_access),
    .penable(apb_access),
    .pwrite(avs_write),
    .paddr(apb_paddr),
    .pwdata(avs_writedata),
    .pstrb(avs_byteenable),
    .prdata(apb_prdata),
    .pready(apb_pready),
    .pslverr(apb_pslverr),
    .uart_txd(uart_txd),
    .uart_rxd(uart_rxd),
    .uart_irq(irq)
  );

  assign avs_readdata    = apb_prdata;
  assign avs_waitrequest = 1'b0;
endmodule
