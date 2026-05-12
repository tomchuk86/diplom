// Вспомогательная логика приёмной линии: длинный break (LSR BI) и таймаут между
// символами в FIFO-режиме (для IIR «character timeout», только при rlv < порога).
`timescale 1ns/1ps
module uart_16550_rx_aux (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        t16,
  input  wire        fifo_en,
  input  wire        rxx,
  input  wire        rxdv,
  input  wire        rpop,
  input  wire        rpsh,
  input  wire [3:0]  rlv,
  input  wire [3:0]  rx_thr,
  input  wire [21:0] to_limit,
  output wire        break_long,
  output wire        rx_to,
  output wire [63:0] line_hist
);

  uart_16550_line_hist u_lh (
    .clk(clk),
    .rst_n(rst_n),
    .en(t16),
    .bit_in(rxx),
    .vec(line_hist)
  );

  reg [8:0] brk_cnt;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      brk_cnt <= 9'd0;
    else if (t16) begin
      if (rxx == 1'b0) begin
        if (brk_cnt < 9'd511)
          brk_cnt <= brk_cnt + 9'd1;
      end else
        brk_cnt <= 9'd0;
    end
  end

  assign break_long = (brk_cnt >= 9'd288);

  reg [21:0] rx_to_cnt;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rx_to_cnt <= 22'd0;
    else if (!fifo_en || (rlv == 4'd0)) begin
      rx_to_cnt <= 22'd0;
    end else if (rxdv) begin
      rx_to_cnt <= 22'd0;
    end else if (rpop || rpsh) begin
      rx_to_cnt <= 22'd0;
    end else if (t16) begin
      if (rx_to_cnt >= to_limit)
        rx_to_cnt <= to_limit;
      else
        rx_to_cnt <= rx_to_cnt + 22'd1;
    end
  end

  assign rx_to = fifo_en && (rlv > 4'd0) && (rlv < rx_thr) && (rx_to_cnt >= to_limit);
endmodule
