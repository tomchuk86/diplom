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
  localparam integer BIT_CYCLES = CLK_HZ / BAUD; // ~434 cycles per UART bit @ 50MHz/115200
  localparam integer USE_DIRECT_UART_DEBUG = 0;
  localparam integer ENABLE_PERIODIC_HELLO = 0;
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
  wire        board_txd;

  // Board wiring:
  // - GPIO_0[0] -> USB-UART RX (FPGA TX output)
  // - GPIO_0[1] <- USB-UART TX (FPGA RX input)
  assign GPIO_0[0] = board_txd;
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

  localparam [5:0]
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
    ST_READ_RBR   = 5'd27,
    ST_ECHO_BYTE  = 6'd30;

  reg [5:0]  st;
  reg [31:0] cnt;
  reg [3:0]  idx;
  reg [7:0]  msg_count;
  reg [7:0]  led_data;
  reg [7:0]  echo_data;
  reg        echo_pending;

  // Direct UART debug transmitter. It bypasses the 16550 core and sends
  // a single 0x55 ('U') byte every second on GPIO_0[0].
  reg        direct_txd;
  reg        direct_busy;
  reg [3:0]  direct_bit_idx;
  reg [3:0]  direct_char_idx;
  reg [15:0] direct_bit_cnt;
  reg [31:0] direct_gap_cnt;
  reg [9:0]  direct_frame;

  function [7:0] direct_char;
    input [3:0] n;
    begin
      case (n)
        4'd0:  direct_char = "H";
        4'd1:  direct_char = "E";
        4'd2:  direct_char = "L";
        4'd3:  direct_char = "L";
        4'd4:  direct_char = "O";
        4'd5:  direct_char = " ";
        4'd6:  direct_char = "F";
        4'd7:  direct_char = "P";
        4'd8:  direct_char = "G";
        4'd9:  direct_char = "A";
        4'd10: direct_char = 8'h0D;
        4'd11: direct_char = 8'h0A;
        default: direct_char = 8'h0A;
      endcase
    end
  endfunction

  assign board_txd = USE_DIRECT_UART_DEBUG ? direct_txd : uart_txd;

  always @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
      direct_txd     <= 1'b1;
      direct_busy    <= 1'b0;
      direct_bit_idx <= 4'd0;
      direct_char_idx <= 4'd0;
      direct_bit_cnt <= 16'd0;
      direct_gap_cnt <= 32'd0;
      direct_frame   <= 10'b11_0101_0101_0; // stop + 0x55 LSB-first + start
    end else if (!direct_busy) begin
      direct_txd <= 1'b1;
      if (direct_gap_cnt == GAP_CYCLES) begin
        direct_gap_cnt <= 32'd0;
        direct_busy    <= 1'b1;
        direct_bit_idx <= 4'd0;
        direct_bit_cnt <= 16'd0;
        direct_char_idx <= 4'd0;
        direct_frame   <= {1'b1, direct_char(4'd0), 1'b0};
        direct_txd     <= 1'b0; // start bit
      end else begin
        direct_gap_cnt <= direct_gap_cnt + 1'b1;
      end
    end else begin
      if (direct_bit_cnt == BIT_CYCLES - 1) begin
        direct_bit_cnt <= 16'd0;
        if (direct_bit_idx == 4'd9) begin
          if (direct_char_idx == 4'd11) begin
            direct_busy <= 1'b0;
            direct_txd  <= 1'b1;
          end else begin
            direct_char_idx <= direct_char_idx + 1'b1;
            direct_bit_idx  <= 4'd0;
            direct_frame    <= {1'b1, direct_char(direct_char_idx + 1'b1), 1'b0};
            direct_txd      <= 1'b0; // next start bit
          end
        end else begin
          direct_bit_idx <= direct_bit_idx + 1'b1;
          direct_txd     <= direct_frame[direct_bit_idx + 1'b1];
        end
      end else begin
        direct_bit_cnt <= direct_bit_cnt + 1'b1;
      end
    end
  end

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
      echo_data <= 8'd0;
      echo_pending <= 1'b0;
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
          else if (echo_pending && prdata[5]) st <= ST_ECHO_BYTE;
          else if (ENABLE_PERIODIC_HELLO && prdata[5]) st <= ST_SEND_BYTE; // THRE
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
          echo_data <= prdata[7:0];
          echo_pending <= 1'b1;
          st <= ST_CHECK_LSR;
        end

        ST_ECHO_BYTE: begin
          apb_write8(8'h00, echo_data); // THR
          st <= ST_ECHO_BYTE + 1;
        end
        ST_ECHO_BYTE+1: begin penable <= 1'b1; st <= ST_ECHO_BYTE + 2; end
        ST_ECHO_BYTE+2: begin
          psel <= 1'b0;
          penable <= 1'b0;
          echo_pending <= 1'b0;
          st <= ST_CHECK_LSR;
        end

        ST_SEND_BYTE: begin
          apb_write8(8'h00, direct_char(idx)); // THR
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
  assign LEDR[9:2] = USE_DIRECT_UART_DEBUG ? 8'h55 : led_data;

endmodule