// Синхронный FIFO: для RX/TX буферов 16550.
module uart_fifo #(
  parameter DEPTH  = 16,
  parameter DW     = 8
) (
  input  wire                 clk,
  input  wire                 rst_n,
  input  wire                 push,
  input  wire                 pop,
  input  wire [DW-1:0]        din,
  output wire [DW-1:0]        dout,
  output wire                 full,
  output wire                 empty,
  input  wire                 flush,
  output wire [$clog2(DEPTH+1)-1:0] level
);

  localparam AW = $clog2(DEPTH > 0 ? DEPTH : 1);
  reg [DW-1:0]  mem[0:DEPTH-1];
  reg [AW-1:0]  wptr;
  reg [AW-1:0]  rptr;
  reg [AW:0]    count;

  assign empty = (count == 0);
  assign full  = (count == DEPTH);
  assign dout  = mem[rptr];
  assign level = count[AW:0];

  integer j;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wptr  <= 0;
      rptr  <= 0;
      count <= 0;
      for (j = 0; j < DEPTH; j = j + 1)
        mem[j] <= {DW{1'b0}};
    end else if (flush) begin
      wptr  <= 0;
      rptr  <= 0;
      count <= 0;
    end else begin
      case ({push & ~full, pop & ~empty})
        2'b10: begin
          mem[wptr] <= din;
          wptr <= wptr + 1'b1;
          count  <= count + 1'b1;
        end
        2'b01: begin
          rptr <= rptr + 1'b1;
          count  <= count - 1'b1;
        end
        2'b11: begin
          mem[wptr] <= din;
          wptr <= wptr + 1'b1;
          rptr <= rptr + 1'b1;
        end
        default: ;
      endcase
    end
  end
endmodule
