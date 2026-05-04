`timescale 1ns/1ps
module de1_soc_uart_top (
  input  wire        CLOCK_50,
  input  wire [3:0]  KEY,
  output wire [9:0]  LEDR,
  inout  wire [35:0] GPIO_0
);
  localparam integer CLK_HZ     = 50000000;
  localparam integer BAUD       = 115200;
  localparam integer DIVISOR    = CLK_HZ / (16 * BAUD); // ~27 for 50MHz/115200
  localparam integer MSG_LEN    = 12;
  // Keep UART traffic sparse to avoid terminal/VM overload.
  localparam integer GAP_CYCLES = 50000000; // 1s @ 50MHz

  // Simple APB3 signals to the UART wrapper.
  reg         psel, penable, pwrite;
  reg  [7:0]  paddr;
  reg  [31:0] pwdata;
  reg  [3:0]  pstrb;
  wire [31:0] prdata;
  wire        pready, pslverr;
  wire        uart_txd;
  wire        uart_irq;
  wire        uart_rxd;

  // Board wiring:
  // - GPIO_0[0] -> USB-UART RX (FPGA TX output)
  // - GPIO_0[1] <- USB-UART TX (FPGA RX input)
  assign GPIO_0[0] = uart_txd;
  assign uart_rxd  = GPIO_0[1];
  assign GPIO_0[35:2] = {34{1'bz}};

  // Active-low pushbutton reset.
  wire rst_n = KEY[0];

  apb_uart_16550 u_uart (
    .pclk(CLOCK_50),
    .presetn(rst_n),
    .psel(psel),
    .penable(penable),
    .pwrite(pwrite),
    .paddr(paddr),
    .pwdata(pwdata),
    .pstrb(pstrb),
    .prdata(prdata),
    .pready(pready),
    .pslverr(pslverr),
    .uart_txd(uart_txd),
    .uart_rxd(uart_rxd),
    .uart_irq(uart_irq)
  );

  // Message sent forever.
  reg [7:0] msg [0:MSG_LEN-1];
  initial begin
    msg[0]  = "H";
    msg[1]  = "E";
    msg[2]  = "L";
    msg[3]  = "L";
    msg[4]  = "O";
    msg[5]  = " ";
    msg[6]  = "F";
    msg[7]  = "P";
    msg[8]  = "G";
    msg[9]  = "A";
    msg[10] = 8'h0D;
    msg[11] = 8'h0A;
  end

  localparam [4:0]
    ST_RESET_WAIT = 5'd0,
    ST_INIT_0     = 5'd1,
    ST_INIT_1     = 5'd4,
    ST_INIT_2     = 5'd7,
    ST_INIT_3     = 5'd10,
    ST_INIT_4     = 5'd13,
    ST_CHECK_LSR  = 5'd16,
    ST_READ_LSR   = 5'd19,
    ST_SEND_BYTE  = 5'd22,
    ST_NEXT_BYTE  = 5'd25,
    ST_GAP        = 5'd26,
    ST_READ_RBR   = 5'd27;

  reg [4:0]  st;
  reg [31:0] cnt;
  reg [3:0]  idx;
  reg [7:0]  msg_count;
  reg [7:0]  led_data;

  // APB single access helper:
  // cycle 1: psel=1,penable=0
  // cycle 2: psel=1,penable=1
  // cycle 3: psel=0,penable=0
  task apb_write8;
    input [7:0] addr;
    input [7:0] data;
    begin
      psel    <= 1'b1;
      penable <= 1'b0;
      pwrite  <= 1'b1;
      paddr   <= addr;
      pwdata  <= {24'd0, data};
      pstrb   <= 4'b0001;
    end
  endtask

  task apb_read8;
    input [7:0] addr;
    begin
      psel    <= 1'b1;
      penable <= 1'b0;
      pwrite  <= 1'b0;
      paddr   <= addr;
      pstrb   <= 4'b0000;
    end
  endtask

  always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
      psel    <= 1'b0;
      penable <= 1'b0;
      pwrite  <= 1'b0;
      paddr   <= 8'd0;
      pwdata  <= 32'd0;
      pstrb   <= 4'd0;
      st      <= ST_RESET_WAIT;
      cnt     <= 32'd0;
      idx     <= 4'd0;
      msg_count <= 8'd0;
      led_data <= 8'd0;
    end else begin
      case (st)
        ST_RESET_WAIT: begin
          cnt <= cnt + 1;
          if (cnt == 32'd10000) begin
            cnt <= 0;
            st  <= ST_INIT_0;
          end
        end

        // LCR=0x80 (DLAB=1)
        ST_INIT_0: begin
          apb_write8(8'h0C, 8'h80);
          st <= ST_INIT_0 + 1;
        end
        ST_INIT_0+1: begin penable <= 1'b1; st <= ST_INIT_0 + 2; end
        ST_INIT_0+2: begin psel <= 1'b0; penable <= 1'b0; st <= ST_INIT_1; end

        // DLL
        ST_INIT_1: begin
          apb_write8(8'h00, DIVISOR[7:0]);
          st <= ST_INIT_1 + 1;
        end
        ST_INIT_1+1: begin penable <= 1'b1; st <= ST_INIT_1 + 2; end
        ST_INIT_1+2: begin psel <= 1'b0; penable <= 1'b0; st <= ST_INIT_2; end

        // DLM=0
        ST_INIT_2: begin
          apb_write8(8'h04, 8'h00);
          st <= ST_INIT_2 + 1;
        end
        ST_INIT_2+1: begin penable <= 1'b1; st <= ST_INIT_2 + 2; end
        ST_INIT_2+2: begin psel <= 1'b0; penable <= 1'b0; st <= ST_INIT_3; end

        // LCR=0x03 (8N1)
        ST_INIT_3: begin
          apb_write8(8'h0C, 8'h03);
          st <= ST_INIT_3 + 1;
        end
        ST_INIT_3+1: begin penable <= 1'b1; st <= ST_INIT_3 + 2; end
        ST_INIT_3+2: begin psel <= 1'b0; penable <= 1'b0; st <= ST_INIT_4; end

        // FCR=0x07 (enable/reset FIFOs)
        ST_INIT_4: begin
          apb_write8(8'h08, 8'h07);
          st <= ST_INIT_4 + 1;
        end
        ST_INIT_4+1: begin penable <= 1'b1; st <= ST_INIT_4 + 2; end
        ST_INIT_4+2: begin
          psel <= 1'b0;
          penable <= 1'b0;
          idx <= 0;
          st <= ST_CHECK_LSR;
        end

        ST_CHECK_LSR: begin
          apb_read8(8'h14); // LSR
          st <= ST_READ_LSR;
        end
        ST_READ_LSR: begin
          penable <= 1'b1;
          st <= ST_READ_LSR + 1;
        end
        ST_READ_LSR+1: begin
          psel <= 1'b0;
          penable <= 1'b0;
          if (prdata[0]) st <= ST_READ_RBR;       // DR: RX data ready
          else if (prdata[5]) st <= ST_SEND_BYTE; // THRE: TX holding register empty
          else st <= ST_CHECK_LSR;
        end

        // Read received byte and mirror it on LEDs[9:2]
        ST_READ_RBR: begin
          apb_read8(8'h00); // RBR
          st <= ST_READ_RBR + 1;
        end
        ST_READ_RBR+1: begin
          penable <= 1'b1;
          st <= ST_READ_RBR + 2;
        end
        ST_READ_RBR+2: begin
          psel <= 1'b0;
          penable <= 1'b0;
          led_data <= prdata[7:0];
          st <= ST_CHECK_LSR;
        end

        ST_SEND_BYTE: begin
          apb_write8(8'h00, msg[idx]); // THR
          st <= ST_SEND_BYTE + 1;
        end
        ST_SEND_BYTE+1: begin penable <= 1'b1; st <= ST_SEND_BYTE + 2; end
        ST_SEND_BYTE+2: begin
          psel <= 1'b0;
          penable <= 1'b0;
          st <= ST_NEXT_BYTE;
        end

        ST_NEXT_BYTE: begin
          if (idx == MSG_LEN-1) begin
            idx <= 0;
            cnt <= 0;
            msg_count <= msg_count + 8'd1;
            st <= ST_GAP;
          end else begin
            idx <= idx + 1;
            st <= ST_CHECK_LSR;
          end
        end

        ST_GAP: begin
          cnt <= cnt + 1;
          if (cnt == GAP_CYCLES) begin
            cnt <= 0;
            st <= ST_CHECK_LSR;
          end
        end

        default: st <= ST_RESET_WAIT;
      endcase
    end
  end

  // LEDs: heartbeat + IRQ monitor.
  assign LEDR[0] = cnt[22];
  assign LEDR[1] = uart_irq;
  assign LEDR[9:2] = led_data;

endmodule