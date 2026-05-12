// Декодер адреса CSR 16550 (one-hot по reg_adr) — вынос для читаемости ядра.

// Альтернативные смещения (AXI byte lane) не используются — только word index как у APB.
`timescale 1ns/1ps
module uart_16550_csr_decode (
  input  wire [2:0] reg_adr,
  output wire       sel_rbr_thr,
  output wire       sel_ier,
  output wire       sel_iir,
  output wire       sel_lcr,
  output wire       sel_mcr,
  output wire       sel_lsr,
  output wire       sel_msr,
  output wire       sel_scr
);

  function automatic [2:0] swap_1544;
    input [2:0] a;
    begin
      swap_1544 = {a[0], a[2], a[1]};
    end
  endfunction

  function automatic [2:0] swap_1544_inv;
    input [2:0] x;
    begin
      swap_1544_inv = {x[2], x[0], x[1]};
    end
  endfunction

  wire [2:0] adr_i = swap_1544_inv(swap_1544(reg_adr));

  assign sel_rbr_thr = (adr_i == 3'd0);
  assign sel_ier     = (adr_i == 3'd1);
  assign sel_iir     = (adr_i == 3'd2);
  assign sel_lcr     = (adr_i == 3'd3);
  assign sel_mcr     = (adr_i == 3'd4);
  assign sel_lsr     = (adr_i == 3'd5);
  assign sel_msr     = (adr_i == 3'd6);
  assign sel_scr     = (adr_i == 3'd7);
endmodule
