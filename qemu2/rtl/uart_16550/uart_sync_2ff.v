// Двухступенчатый синхронизатор 1 бита (метастабильность -> CDC из асинхронного rxd в pclk).
// Сброс в «idle» линии UART (лог. 1).
`timescale 1ns/1ps
module uart_sync_2ff (
  input  wire clk,
  input  wire rst_n,
  input  wire din,
  output reg  dout
);
  reg s0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s0   <= 1'b1;
      dout <= 1'b1;
    end else begin
      s0   <= din;
      dout <= s0;
    end
  end
endmodule
