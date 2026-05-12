// MCR/MSR по мотивам 16550: CTS/DSR/RI/DCD, дельта-биты, loopback (RTS→CTS, DTR→DSR,
// OUT1→RI, OUT2→DCD). Внешние входы — два ступени FF; из loopback — синхронно с MCR.
`timescale 1ns/1ps
module uart_16550_modem (
  input  wire       clk,
  input  wire       rst_n,
  input  wire [4:0] mcr,
  input  wire       msr_read,
  input  wire       cts_in,
  input  wire       dsr_in,
  input  wire       ri_in,
  input  wire       dcd_in,
  output reg  [7:0] msr,
  output wire       irq_pending
);

  wire lb = mcr[4];

  reg [1:0] cf_cts, cf_dsr, cf_ri, cf_dcd;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cf_cts <= 2'b00;
      cf_dsr <= 2'b00;
      cf_ri  <= 2'b00;
      cf_dcd <= 2'b00;
    end else begin
      cf_cts <= {cf_cts[0], cts_in};
      cf_dsr <= {cf_dsr[0], dsr_in};
      cf_ri  <= {cf_ri[0], ri_in};
      cf_dcd <= {cf_dcd[0], dcd_in};
    end
  end

  wire cts_ext = cf_cts[1];
  wire dsr_ext = cf_dsr[1];
  wire ri_ext  = cf_ri[1];
  wire dcd_ext = cf_dcd[1];

  wire cts_eff = lb ? mcr[1] : cts_ext;
  wire dsr_eff = lb ? mcr[0] : dsr_ext;
  wire ri_eff  = lb ? mcr[2] : ri_ext;
  wire dcd_eff = lb ? mcr[3] : dcd_ext;

  reg cts_q, dsr_q, ri_q, dcd_q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cts_q <= 1'b0;
      dsr_q <= 1'b0;
      ri_q  <= 1'b1;
      dcd_q <= 1'b1;
      msr   <= 8'hB0;
    end else begin
      msr[4] <= cts_eff;
      msr[5] <= dsr_eff;
      msr[6] <= ri_eff;
      msr[7] <= dcd_eff;

      if (msr_read) begin
        msr[0] <= 1'b0;
        msr[1] <= 1'b0;
        msr[2] <= 1'b0;
        msr[3] <= 1'b0;
      end else begin
        if (cts_eff != cts_q)
          msr[0] <= 1'b1;
        if (dsr_eff != dsr_q)
          msr[1] <= 1'b1;
        if (ri_q & ~ri_eff)
          msr[2] <= 1'b1;
        if (dcd_eff != dcd_q)
          msr[3] <= 1'b1;
      end

      cts_q <= cts_eff;
      dsr_q <= dsr_eff;
      ri_q  <= ri_eff;
      dcd_q <= dcd_eff;
    end
  end

  assign irq_pending = msr[0] | msr[1] | msr[2] | msr[3];

endmodule
