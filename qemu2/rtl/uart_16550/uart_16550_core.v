// 16550A-подобный UART, рег. чтение комбинат.
`timescale 1ns/1ps
module uart_16550_core (
  input  wire         clk, rst_n, rxd_in,
  output wire         txd_out, output reg intr,
  /* Standard 16550 regs: widx[2:0] 0..7  -> byte offsets 0x00,0x04,..,0x1C */
  input  wire [2:0]   reg_adr,
  /* APB word index paddr[7:2]; 8..11 -> extension TX/RX/ERR/IRQ counts (demo/QEMU) */
  input  wire [5:0]   widx,
  input  wire         reg_we, reg_re,
  input  wire [7:0]   wdata8,
  output reg  [7:0]   rdata8,
  output reg  [31:0]  rdata32
);
  localparam D = 8;
  reg [7:0] dll, dlh, ier, fcr, lcr, scr, lsr, iir, msr;
  reg [4:0] mcr4;  // MCR[4] = loopback (16550)
  reg ovr, s_pe, s_fe;
  reg [31:0] stat_tx, stat_rx, stat_err, stat_irq;
  reg        intr_d;
  /* uart_rx holds valid across many clk until next tick_16x — count one push/err per byte */
  reg        rxdv_d;
  wire dlab  = lcr[7];
  wire [1:0] wl  = lcr[1:0];
  wire st2 = lcr[2], pen = lcr[3], pse = lcr[4], brk  = lcr[6];
  // baud
  wire t16; uart_baud u_bd( .clk(clk), .rst_n(rst_n), .divisor({dlh, dll}), .tick_16x(t16) );
  // TX: сначала сигналы, потом loopback (txd_w нужен в always)
  wire  txd_w, ubsy; reg  us; reg[7:0] ud;
  uart_tx u_tx( .clk(clk), .rst_n(rst_n), .tick_16x(t16), .start(us), .start_data(ud), .wl(wl), .st2(st2), .pen(pen), .pse(pse), .txd(txd_w), .busy(ubsy) );
  assign txd_out = brk?1'b0:txd_w;
  reg  rxx; always @* rxx = mcr4[4] ? txd_w : rxd_in;
  // rx
  wire rxdv; wire[7:0] rxb; wire ffe, fpe;
  uart_rx u_rx( .clk(clk), .rst_n(rst_n), .tick_16x(t16), .rxd(rxx), .wl(wl), .st2(st2), .pen(pen), .pse(pse), .dly_en(1'b1),
    .valid(rxdv), .dout(rxb), .frame_err(ffe), .parity_err(fpe) );
  // fifo: rpop — только comb (дубль reg убран)
  reg  tpsh, tpop, rpsh, tfl, rfl; reg[7:0] tdi, rdi; wire[7:0] tdo, rdo; wire tff, tmt, rff, rmt; wire [3:0] tlv, rlv;
  wire  rpop  = reg_re & (reg_adr==3'd0) & ~dlab;
  uart_fifo #(.DEPTH(D), .DW(8)) u_tf( .clk(clk), .rst_n(rst_n), .push(tpsh), .pop(tpop), .din(tdi), .dout(tdo), .full(tff), .empty(tmt), .flush(tfl), .level(tlv) );
  uart_fifo #(.DEPTH(D), .DW(8)) u_rf( .clk(clk), .rst_n(rst_n), .push(rpsh), .pop(rpop), .din(rdi), .dout(rdo), .full(rff), .empty(rmt), .flush(rfl), .level(rlv) );
  // TX
  reg [2:0] tsm; reg [7:0] tcap;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) tsm  <= 0; else begin
      us  <= 0; tpop  <= 0;
      case (tsm)
        0: if (!tmt && !ubsy) tsm  <= 1;
        1: begin tcap  <= tdo; tpop  <= 1; tsm  <= 2; end
        2: begin us  <= 1; ud  <= tcap; tsm  <= 3; end
        3: if (ubsy) tsm  <= 4;
        4: if (!ubsy) tsm  <= 0;
        default: tsm  <= 0;
      endcase
    end
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dll  <= 1; dlh  <= 0; ier  <= 0; fcr  <= 0; lcr  <= 8'h03; mcr4  <= 0; scr  <= 0; msr  <= 8'hB0; ovr  <= 0; s_pe  <= 0; s_fe  <= 0;
      stat_tx  <= 0; stat_rx  <= 0; stat_err  <= 0; stat_irq  <= 0; intr_d  <= 0;
      rxdv_d   <= 1'b0;
    end else begin
      tpsh  <= 0; rpsh  <= 0; tfl  <= 0; rfl  <= 0;
      if (reg_we & (widx < 6'd8) & (reg_adr == 3'd0) & ~dlab) stat_tx  <= stat_tx + 1;
      if (rpop & ~rmt) stat_rx  <= stat_rx + 1;
      if (rxdv & ~rxdv_d) begin
        rdi  <= rxb; rpsh  <= 1;
        if (rff) begin
          ovr  <= 1;
          stat_err  <= stat_err + 1;
        end else if (fpe) begin
          s_pe  <= 1;
          stat_err  <= stat_err + 1;
        end else if (ffe) begin
          s_fe  <= 1;
          stat_err  <= stat_err + 1;
        end
      end
      rxdv_d  <= rxdv;
      if (reg_we & (widx >= 6'd8) & (widx <= 6'd11)) begin
        case (widx)
          6'd8:  stat_tx  <= 0;
          6'd9:  stat_rx  <= 0;
          6'd10: begin stat_err <= 0; ovr <= 0; s_pe <= 0; s_fe <= 0; end
          6'd11: stat_irq <= 0;
          default: ;
        endcase
      end
      if (reg_we & (widx < 6'd8)) case (reg_adr)
        0: if (dlab) dll  <= wdata8; else begin tdi  <= wdata8; tpsh  <= 1; end
        1: if (dlab) dlh  <= wdata8; else ier  <= wdata8 & 8'h0F;
        2: begin
          fcr  <= wdata8;
          if (wdata8[1]) tfl  <= 1;
          if (wdata8[2]) begin rfl <= 1; ovr <= 0; s_pe <= 0; s_fe <= 0; end
        end
        3: lcr  <= wdata8; 4: mcr4  <= wdata8[4:0]; 7: scr  <= wdata8;
        default: ;
      endcase
      if (intr & ~intr_d) stat_irq  <= stat_irq + 1;
      intr_d  <= intr;
    end
  end
  // lsr+irq
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      lsr  <= 8'h60;
    else begin
      lsr[0]  <= !rmt; lsr[1]  <= ovr; lsr[2]  <= s_pe; lsr[3]  <= s_fe; lsr[4]  <= 0; lsr[5]  <= !tff; lsr[6]  <= tmt & ~ubsy; lsr[7]  <= 0;
    end
  end
  always @* begin
    case (reg_adr)
      0: rdata8  = dlab ? dll : (rmt ? 8'd0 : rdo);
      1: rdata8  = dlab ? dlh : {4'b0, ier[3:0]};
      2: rdata8  = {4'b0, iir[3:0]};
      3: rdata8  = lcr; 4: rdata8  = {3'b0, mcr4};
      5: rdata8  = lsr; 6: rdata8  = 8'h10; 7: rdata8  = scr;
      default: rdata8  = 8'd0;
    endcase
  end
  /* 32-bit read: standard regs in low byte, extension words 8..11 = demo counters @ 0x20..0x2C */
  always @* begin
    rdata32 = {24'd0, rdata8};
    if (widx == 6'd8)  rdata32 = stat_tx;
    if (widx == 6'd9)  rdata32 = stat_rx;
    if (widx == 6'd10) rdata32 = stat_err;
    if (widx == 6'd11) rdata32 = stat_irq;
  end
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      iir  <= 8'h01;
    else if (ier[0] & !rmt)
      begin  iir[3:0]  <= 4'b0100;  iir[0]  <= 0;  end
    else if (ier[1] & !tff)
      begin  iir[3:0]  <= 4'b0010;  iir[0]  <= 0;  end
    else if (ier[2] & (ovr | s_pe | s_fe))
      begin  iir[3:0]  <= 4'b0110;  iir[0]  <= 0;  end
    else
      begin  iir[3:1]  <= 0;  iir[0]  <= 1;  end
  end
  always @* intr  = (ier[0] & !rmt) | (ier[1] & !tff) | (ier[2] & (ovr | s_pe | s_fe));
endmodule
