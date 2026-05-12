// 16550A-подобный UART: CDC на rxd, FIFO/таймаут, MSR/MCR, расширенная MMIO-зона.
`timescale 1ns/1ps
module uart_16550_core (
  input  wire         clk, rst_n, rxd_in,
  output wire         txd_out, output reg intr,
  input  wire [2:0]   reg_adr,
  input  wire [5:0]   widx,
  input  wire         reg_we, reg_re,
  input  wire [7:0]   wdata8,
  input  wire [31:0]  wdata32,
  output reg  [7:0]   rdata8,
  output reg  [31:0]  rdata32
);
  localparam D = 8;

  wire sel_rbr_thr, sel_ier, sel_iir, sel_lcr, sel_mcr, sel_lsr, sel_msr, sel_scr;
  uart_16550_csr_decode u_csr (
    .reg_adr(reg_adr),
    .sel_rbr_thr(sel_rbr_thr),
    .sel_ier(sel_ier),
    .sel_iir(sel_iir),
    .sel_lcr(sel_lcr),
    .sel_mcr(sel_mcr),
    .sel_lsr(sel_lsr),
    .sel_msr(sel_msr),
    .sel_scr(sel_scr)
  );

  wire rxd_sync;
  uart_sync_2ff u_rxd_cdc (
    .clk(clk),
    .rst_n(rst_n),
    .din(rxd_in),
    .dout(rxd_sync)
  );

  reg [7:0] dll, dlh, ier, fcr, lcr, scr, lsr, iir;
  reg [4:0] mcr5;
  reg ovr, s_pe, s_fe;
  reg [31:0] stat_tx, stat_rx, stat_err, stat_irq;
  reg [31:0] scratch0, scratch1;
  reg        intr_d;
  reg        rxdv_d;

  wire dlab  = lcr[7];
  wire [1:0] wl  = lcr[1:0];
  wire st2 = lcr[2], pen = lcr[3], pse = lcr[4], brk  = lcr[6];
  wire fifo_en = fcr[0];

  reg [3:0] rx_thr;
  always @* begin
    case (fcr[7:6])
      2'b00:   rx_thr = 4'd1;
      2'b01:   rx_thr = 4'd2;
      2'b10:   rx_thr = 4'd4;
      default: rx_thr = 4'd7;
    endcase
  end

  wire [15:0] div = ({dlh, dll} == 16'd0) ? 16'd1 : {dlh, dll};
  wire [21:0] to_limit = {6'd0, div} * 22'd40;

  wire t16;
  uart_baud u_bd (
    .clk(clk), .rst_n(rst_n), .divisor({dlh, dll}), .tick_16x(t16)
  );

  wire  txd_w, ubsy;
  reg   us;
  reg [7:0] ud;
  uart_tx u_tx (
    .clk(clk), .rst_n(rst_n), .tick_16x(t16), .start(us), .start_data(ud),
    .wl(wl), .st2(st2), .pen(pen), .pse(pse), .txd(txd_w), .busy(ubsy)
  );
  assign txd_out = brk ? 1'b0 : txd_w;

  wire rxx;
  assign rxx = mcr5[4] ? txd_w : rxd_sync;

  wire rxdv;
  wire [7:0] rxb;
  wire ffe, fpe;
  uart_rx u_rx (
    .clk(clk), .rst_n(rst_n), .tick_16x(t16), .rxd(rxx), .wl(wl), .st2(st2),
    .pen(pen), .pse(pse), .dly_en(1'b1),
    .valid(rxdv), .dout(rxb), .frame_err(ffe), .parity_err(fpe)
  );

  reg  tpsh, tpop, rpsh, tfl, rfl;
  reg [7:0] tdi, rdi;
  wire [7:0] tdo, rdo;
  wire tff, tmt, rff, rmt;
  wire [3:0] tlv, rlv;

  wire rpop = reg_re & sel_rbr_thr & ~dlab;

  uart_fifo #(.DEPTH(D), .DW(8)) u_tf (
    .clk(clk), .rst_n(rst_n), .push(tpsh), .pop(tpop), .din(tdi), .dout(tdo),
    .full(tff), .empty(tmt), .flush(tfl), .level(tlv)
  );
  uart_fifo #(.DEPTH(D), .DW(8)) u_rf (
    .clk(clk), .rst_n(rst_n), .push(rpsh), .pop(rpop), .din(rdi), .dout(rdo),
    .full(rff), .empty(rmt), .flush(rfl), .level(rlv)
  );

  wire break_long;
  wire rx_to;
  wire [63:0] line_hist;
  uart_16550_rx_aux u_rx_aux (
    .clk(clk),
    .rst_n(rst_n),
    .t16(t16),
    .fifo_en(fifo_en),
    .rxx(rxx),
    .rxdv(rxdv),
    .rpop(rpop),
    .rpsh(rpsh),
    .rlv(rlv),
    .rx_thr(rx_thr),
    .to_limit(to_limit),
    .break_long(break_long),
    .rx_to(rx_to),
    .line_hist(line_hist)
  );

  wire rx_rda = fifo_en ? (rlv >= rx_thr) : !rmt;

  wire msr_rd = reg_re & sel_msr & (widx < 6'd8);
  wire [7:0] msr;
  wire modem_irq;
  uart_16550_modem u_modem (
    .clk(clk),
    .rst_n(rst_n),
    .mcr(mcr5),
    .msr_read(msr_rd),
    .cts_in(1'b0),
    .dsr_in(1'b0),
    .ri_in(1'b1),
    .dcd_in(1'b1),
    .msr(msr),
    .irq_pending(modem_irq)
  );

  wire dma_we = reg_we & (widx >= 6'd16) & (widx <= 6'd19);
  wire [1:0] dma_addr = widx[1:0];
  wire [31:0] dma_rdata;
  uart_16550_dma_port u_dma (
    .clk(clk),
    .rst_n(rst_n),
    .we(dma_we),
    .addr(dma_addr),
    .wdata(wdata32),
    .rdata(dma_rdata)
  );

  wire        bucket_we = reg_we & (widx >= 6'd20) & (widx <= 6'd39);
  wire [5:0]  bucket_off = widx - 6'd20;
  wire [4:0]  bucket_sel = bucket_off[4:0];
  wire [31:0] bucket_rdata;
  uart_16550_mmio_bucket u_mmio (
    .clk(clk),
    .rst_n(rst_n),
    .we(bucket_we),
    .sel(bucket_sel),
    .wdata(wdata32),
    .rdata(bucket_rdata)
  );

  reg [2:0] tsm;
  reg [7:0] tcap;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      tsm <= 3'd0;
    else begin
      us   <= 1'b0;
      tpop <= 1'b0;
      case (tsm)
        3'd0: if (!tmt && !ubsy)
          tsm <= 3'd1;
        3'd1: begin
          tcap <= tdo;
          tpop <= 1'b1;
          tsm  <= 3'd2;
        end
        3'd2: begin
          us  <= 1'b1;
          ud  <= tcap;
          tsm <= 3'd3;
        end
        3'd3: if (ubsy)
          tsm <= 3'd4;
        3'd4: if (!ubsy)
          tsm <= 3'd0;
        default: tsm <= 3'd0;
      endcase
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dll <= 1;
      dlh <= 0;
      ier <= 0;
      fcr <= 0;
      lcr <= 8'h03;
      mcr5 <= 0;
      scr <= 0;
      scratch0 <= 32'd0;
      scratch1 <= 32'd0;
      ovr <= 0;
      s_pe <= 0;
      s_fe <= 0;
      stat_tx <= 0;
      stat_rx <= 0;
      stat_err <= 0;
      stat_irq <= 0;
      intr_d <= 0;
      rxdv_d <= 1'b0;
    end else begin
      tpsh <= 0;
      rpsh <= 0;
      tfl <= 0;
      rfl <= 0;
      if (reg_we & (widx < 6'd8) & (reg_adr == 3'd0) & ~dlab)
        stat_tx <= stat_tx + 1;
      if (rpop & ~rmt)
        stat_rx <= stat_rx + 1;
      if (rxdv & ~rxdv_d) begin
        rdi <= rxb;
        rpsh <= 1;
        if (rff) begin
          ovr <= 1;
          stat_err <= stat_err + 1;
        end else if (fpe) begin
          s_pe <= 1;
          stat_err <= stat_err + 1;
        end else if (ffe) begin
          s_fe <= 1;
          stat_err <= stat_err + 1;
        end
      end
      rxdv_d <= rxdv;
      if (reg_we & (widx >= 6'd8) & (widx <= 6'd11)) begin
        case (widx)
          6'd8:  stat_tx <= 0;
          6'd9:  stat_rx <= 0;
          6'd10: begin stat_err <= 0; ovr <= 0; s_pe <= 0; s_fe <= 0; end
          6'd11: stat_irq <= 0;
          default: ;
        endcase
      end
      if (reg_we & (widx == 6'd12))
        scratch0 <= wdata32;
      if (reg_we & (widx == 6'd13))
        scratch1 <= wdata32;
      if (reg_we & (widx < 6'd8))
        case (reg_adr)
          0: if (dlab) dll <= wdata8; else begin tdi <= wdata8; tpsh <= 1; end
          1: if (dlab) dlh <= wdata8; else ier <= wdata8 & 8'h0F;
          2: begin
            fcr <= wdata8;
            if (wdata8[1]) tfl <= 1;
            if (wdata8[2]) begin rfl <= 1; ovr <= 0; s_pe <= 0; s_fe <= 0; end
          end
          3: lcr <= wdata8;
          4: mcr5 <= wdata8[4:0];
          7: scr <= wdata8;
          default: ;
        endcase
      if (intr & ~intr_d)
        stat_irq <= stat_irq + 1;
      intr_d <= intr;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      lsr <= 8'h60;
    else begin
      lsr[0] <= !rmt;
      lsr[1] <= ovr;
      lsr[2] <= s_pe;
      lsr[3] <= s_fe;
      lsr[4] <= break_long;
      lsr[5] <= !tff;
      lsr[6] <= tmt & ~ubsy;
      lsr[7] <= 0;
    end
  end

  always @* begin
    case (reg_adr)
      0: rdata8 = dlab ? dll : (rmt ? 8'd0 : rdo);
      1: rdata8 = dlab ? dlh : {4'b0, ier[3:0]};
      2: rdata8 = {4'b0, iir[3:0]};
      3: rdata8 = lcr;
      4: rdata8 = {3'b0, mcr5};
      5: rdata8 = lsr;
      6: rdata8 = msr;
      7: rdata8 = scr;
      default: rdata8 = 8'd0;
    endcase
  end

  always @* begin
    rdata32 = {24'd0, rdata8};
    if (widx == 6'd8)  rdata32 = stat_tx;
    if (widx == 6'd9)  rdata32 = stat_rx;
    if (widx == 6'd10) rdata32 = stat_err;
    if (widx == 6'd11) rdata32 = stat_irq;
    if (widx == 6'd12) rdata32 = scratch0;
    if (widx == 6'd13) rdata32 = scratch1;
    if (widx == 6'd14) rdata32 = 32'h55415254;
    if (widx == 6'd15) rdata32 = 32'h00010203;
    if ((widx >= 6'd16) && (widx <= 6'd19))
      rdata32 = dma_rdata;
    if ((widx >= 6'd20) && (widx <= 6'd39))
      rdata32 = bucket_rdata;
  end

  /* IIR: RLS > RDA > RX timeout (FIFO) > THRE > modem; нет прерывания = 8'h01. */
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      iir <= 8'h01;
    else if (ier[2] & (ovr | s_pe | s_fe | break_long))
      iir <= {4'b0000, 4'b0110};
    else if (ier[0] & rx_rda)
      iir <= {4'b0000, 4'b0100};
    else if (ier[0] & rx_to)
      iir <= {4'b0000, 4'b1100};
    else if (ier[1] & !tff)
      iir <= {4'b0000, 4'b0010};
    else if (ier[3] & modem_irq)
      iir <= 8'h00;
    else
      iir <= 8'h01;
  end

  always @* intr = (ier[2] & (ovr | s_pe | s_fe | break_long))
                 | (ier[0] & (rx_rda | rx_to))
                 | (ier[1] & !tff)
                 | (ier[3] & modem_irq);
endmodule
