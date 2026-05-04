// UART приём, 16x. Фазы: start, data(5–8), опц. чётность, 1/2 stop.
`timescale 1ns/1ps
module uart_rx (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        tick_16x,
  input  wire        rxd,
  input  wire [1:0]  wl,
  input  wire        st2,
  input  wire        pen, pse,
  input  wire        dly_en,
  output reg         valid,
  output reg  [7:0]  dout,
  output reg         frame_err,
  output reg         parity_err
);

  reg  f0, f1;
  wire rxi = dly_en ? f1 : rxd;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin f0 <= 1; f1 <= 1; end
    else if (dly_en) begin f0 <= rxd; f1 <= f0; end
    else begin f0 <= rxd; f1 <= rxd; end
  end

  function [2:0] w_last;
    input [1:0] w;
    case (w)
      2'b00: w_last = 3'd4;
      2'b01: w_last = 3'd5;
      2'b10: w_last = 3'd6;
      default: w_last = 3'd7;
    endcase
  endfunction

  function f_pexp;
    input [7:0] d8;
    input [1:0] w;
    input       odd;
    reg   [4:0] t5; reg [5:0] t6; reg [6:0] t7; reg p;
    begin
      case (w)
        2'b00: begin t5 = d8[4:0]; p = odd ? ~^{t5} : ^{t5}; end
        2'b01: begin t6 = d8[5:0]; p = odd ? ~^{t6} : ^{t6}; end
        2'b10: begin t7 = d8[6:0]; p = odd ? ~^{t7} : ^{t7}; end
        default: p = odd ? ~^{d8} : ^{d8};
      endcase
      f_pexp = p;
    end
  endfunction

  localparam S0=0, S1=1, S2=2, S5=5, S3=3, S4=4;

  reg [2:0]  st;
  reg [3:0]  tc;
  reg [2:0]  bi;
  reg [2:0]  blast;
  reg [7:0]  dreg;
  reg        parv;
  reg        st2r;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st  <= S0; tc <= 0; bi <= 0; dreg <= 0; parv <= 0;
      valid <= 0; frame_err <= 0; parity_err <= 0; dout <= 0; st2r <= 0;
    end else if (tick_16x) begin
      valid  <= 0; frame_err <= 0; parity_err <= 0;
      case (st)
        S0: begin
          tc <= 0; bi <= 0; dreg <= 0; parv <= 0; st2r <= st2;
          if (rxi == 1'b0) begin
            st  <= S1; tc <= 0; blast <= w_last(wl);
          end
        end
        S1: begin
          if (tc == 4'd7 && rxi != 1'b0) begin
            st  <= S0; tc <= 0; frame_err <= 1'b1;
          end else if (tc == 4'd15) begin
            st  <= S2; tc <= 0; bi <= 0;
          end else
            tc  <= tc + 1'b1;
        end
        S2: begin
          if (tc == 4'd7)
            dreg  <= {rxi, dreg[7:1]};
          if (tc == 4'd15) begin
            tc  <= 0;
            if (bi < blast)
              bi  <= bi + 1'b1;
            else begin
              st  <= pen ? S5 : S3; tc <= 0;
            end
          end else
            tc  <= tc + 1'b1;
        end
        S5: begin
          if (tc == 4'd7)
            parv  <= rxi;
          if (tc == 4'd15) begin
            st  <= S3; tc <= 0;
          end else
            tc  <= tc + 1'b1;
        end
        S3: begin
          if (tc == 4'd7) begin
            if (rxi == 1'b0)
              frame_err  <= 1'b1;
          end
          if (tc == 4'd15) begin
            if (st2r) begin
              st  <= S4; tc <= 0;
            end else begin
              dout  <= dreg;
              valid <= 1'b1;
              if (pen && (parv != f_pexp(dreg, wl, pse)))
                parity_err  <= 1'b1;
              st  <= S0;
            end
          end else
            tc  <= tc + 1'b1;
        end
        S4: begin
          if (tc == 4'd7) begin
            if (rxi == 1'b0)
              frame_err  <= 1'b1;
          end
          if (tc == 4'd15) begin
            dout  <= dreg;
            valid <= 1'b1;
            if (pen && (parv != f_pexp(dreg, wl, pse)))
              parity_err  <= 1'b1;
            st  <= S0;
          end else
            tc  <= tc + 1'b1;
        end
        default: st <= S0;
      endcase
    end
  end
endmodule
