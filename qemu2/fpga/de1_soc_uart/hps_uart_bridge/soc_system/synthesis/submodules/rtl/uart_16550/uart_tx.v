// Передатчик UART: 16x оверсэмплинг, 5–8 бит, чётность, 1/2 стоп.
module uart_tx (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        tick_16x,
  input  wire        start,
  input  wire [7:0]  start_data,
  input  wire [1:0]  wl,      // 00=5, 01=6, 10=7, 11=8
  input  wire        st2,     // 0: 1 stop; 1: 2 stop
  input  wire        pen,     // parity enable
  input  wire        pse,     // 0: even, 1: odd
  output reg         txd,
  output reg         busy
);

  localparam [2:0] S_IDLE   = 0;
  localparam [2:0] S_START  = 1;
  localparam [2:0] S_DATA   = 2;
  localparam [2:0] S_PAR    = 3;
  localparam [2:0] S_STOP1  = 4;
  localparam [2:0] S_STOP2  = 5;

  reg [2:0]  state;
  reg [3:0]  scnt;
  reg [2:0]  bidx;
  reg [2:0]  blast;
  reg [7:0]  dr;
  reg        pb;

  function [2:0] last_index;
    input [1:0] w;
    case (w)
      2'b00: last_index = 3'd4;
      2'b01: last_index = 3'd5;
      2'b10: last_index = 3'd6;
      default: last_index = 3'd7;
    endcase
  endfunction

  function pbit;
    input [7:0] d;
    input [1:0] w;
    input       odd;
    reg   [4:0] t5;
    reg   [5:0] t6;
    reg   [6:0] t7;
    begin
      case (w)
        2'b00: begin
          t5 = d[4:0];
          pbit = odd ? ^{t5} : ~^{t5};
        end
        2'b01: begin
          t6 = d[5:0];
          pbit = odd ? ^{t6} : ~^{t6};
        end
        2'b10: begin
          t7 = d[6:0];
          pbit = odd ? ^{t7} : ~^{t7};
        end
        default: pbit = odd ? ^{d} : ~^{d};
      endcase
    end
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      scnt  <= 0;
      bidx  <= 0;
      txd   <= 1'b1;
      busy  <= 1'b0;
      dr    <= 0;
      pb    <= 0;
      blast <= 0;
    end else if (state == S_IDLE) begin
      if (start) begin
        dr    <= start_data;
        blast <= last_index(wl);
        state <= S_START;
        scnt  <= 0;
        bidx  <= 0;
        txd   <= 1'b0;
        busy  <= 1'b1;
        pb    <= pbit(start_data, wl, pse);
      end
    end else if (tick_16x) begin
      if (scnt != 4'd15) begin
        scnt <= scnt + 1'b1;
      end else begin
        scnt <= 0;
        case (state)
          S_START: begin
            state <= S_DATA;
            txd   <= dr[0];
            dr    <= {1'b0, dr[7:1]};
          end
          S_DATA: begin
            if (bidx == blast) begin
              if (pen) begin
                state <= S_PAR;
                txd   <= pb;
              end else begin
                state <= S_STOP1;
                txd   <= 1'b1;
              end
            end else begin
              bidx  <= bidx + 1'b1;
              txd   <= dr[0];
              dr    <= {1'b0, dr[7:1]};
            end
          end
          S_PAR: begin
            if (st2) begin
              state <= S_STOP1;
              txd   <= 1'b1;
            end else begin
              state <= S_STOP1;
              txd   <= 1'b1;
            end
          end
          S_STOP1: begin
            txd  <= 1'b1;
            if (st2) begin
              state <= S_STOP2;
            end else begin
              state <= S_IDLE;
              busy  <= 1'b0;
            end
          end
          S_STOP2: begin
            txd   <= 1'b1;
            state <= S_IDLE;
            busy  <= 1'b0;
          end
          default: state <= S_IDLE;
        endcase
      end
    end
  end
endmodule
