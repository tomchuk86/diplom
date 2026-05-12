`timescale 1ns/1ps
// Генератор таймингов UART: 16x оверсэмплинг (как в 16550A).
// f_baud = f_clk / (16 * {DLH, DLL}), при 0 в делителе используется 1.
module uart_baud #(
  parameter WIDTH = 16
) (
  input  wire                clk,
  input  wire                rst_n,
  input  wire [WIDTH-1:0]    divisor,   // {DLH, DLL}
  output reg                 tick_16x   // один тик = 1/16 битового интервала
);

  function automatic [WIDTH-1:0] eff_div;
    input [WIDTH-1:0] d;
    begin
      eff_div = (d == 16'd0) ? 16'd1 : d;
    end
  endfunction

  reg [WIDTH-1:0] cnt;
  wire [WIDTH-1:0] d = eff_div(divisor);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt     <= {WIDTH{1'b0}};
      tick_16x <= 1'b0;
    end else begin
      tick_16x <= 1'b0;
      if (cnt + 1'b1 >= d) begin
        cnt     <= {WIDTH{1'b0}};
        tick_16x <= 1'b1;
      end else
        cnt <= cnt + 1'b1;
    end
  end
endmodule
