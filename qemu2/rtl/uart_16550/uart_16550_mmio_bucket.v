// Доп. MMIO-блок: 20×32 регистра (слов widx 20..39).
`timescale 1ns/1ps
module uart_16550_mmio_bucket (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        we,
  input  wire [4:0]  sel,
  input  wire [31:0] wdata,
  output reg  [31:0] rdata
);

  reg [31:0] g0, g1, g2, g3, g4, g5, g6, g7;
  reg [31:0] g8, g9, g10, g11, g12, g13, g14, g15;
  reg [31:0] g16, g17, g18, g19;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      g0 <= 32'd0;
      g1 <= 32'd0;
      g2 <= 32'd0;
      g3 <= 32'd0;
      g4 <= 32'd0;
      g5 <= 32'd0;
      g6 <= 32'd0;
      g7 <= 32'd0;
      g8 <= 32'd0;
      g9 <= 32'd0;
      g10 <= 32'd0;
      g11 <= 32'd0;
      g12 <= 32'd0;
      g13 <= 32'd0;
      g14 <= 32'd0;
      g15 <= 32'd0;
      g16 <= 32'd0;
      g17 <= 32'd0;
      g18 <= 32'd0;
      g19 <= 32'd0;
    end else if (we) begin
      case (sel)
        5'd0:  g0  <= wdata;
        5'd1:  g1  <= wdata;
        5'd2:  g2  <= wdata;
        5'd3:  g3  <= wdata;
        5'd4:  g4  <= wdata;
        5'd5:  g5  <= wdata;
        5'd6:  g6  <= wdata;
        5'd7:  g7  <= wdata;
        5'd8:  g8  <= wdata;
        5'd9:  g9  <= wdata;
        5'd10: g10 <= wdata;
        5'd11: g11 <= wdata;
        5'd12: g12 <= wdata;
        5'd13: g13 <= wdata;
        5'd14: g14 <= wdata;
        5'd15: g15 <= wdata;
        5'd16: g16 <= wdata;
        5'd17: g17 <= wdata;
        5'd18: g18 <= wdata;
        default: g19 <= wdata;
      endcase
    end
  end

  always @* begin
    case (sel)
      5'd0:    rdata = g0;
      5'd1:    rdata = g1;
      5'd2:    rdata = g2;
      5'd3:    rdata = g3;
      5'd4:    rdata = g4;
      5'd5:    rdata = g5;
      5'd6:    rdata = g6;
      5'd7:    rdata = g7;
      5'd8:    rdata = g8;
      5'd9:    rdata = g9;
      5'd10:   rdata = g10;
      5'd11:   rdata = g11;
      5'd12:   rdata = g12;
      5'd13:   rdata = g13;
      5'd14:   rdata = g14;
      5'd15:   rdata = g15;
      5'd16:   rdata = g16;
      5'd17:   rdata = g17;
      5'd18:   rdata = g18;
      default: rdata = g19;
    endcase
  end
endmodule
