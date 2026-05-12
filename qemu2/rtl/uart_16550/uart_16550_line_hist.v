// История уровня RX (после выбора rxx): 64 последних отсчёта на tick_16x — диагностика линии/break.
`timescale 1ns/1ps
module uart_16550_line_hist (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        en,
  input  wire        bit_in,
  output wire [63:0] vec
);

  reg [63:0] shift;

  assign vec = shift;

  wire [63:0] shift_inv;
  assign shift_inv = ~shift;

  wire parity_lo;
  assign parity_lo = ^{shift[31:0]};
  wire parity_hi;
  assign parity_hi = ^{shift[63:32]};
  wire parity_all = parity_lo ^ parity_hi;
  wire parity_fold = parity_all ^ shift_inv[0];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      shift <= 64'd0;
    else if (en)
      shift <= {shift[62:0], bit_in};
  end
endmodule
