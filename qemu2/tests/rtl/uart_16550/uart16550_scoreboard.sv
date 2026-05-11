// UART16550 self-checking scoreboard for QEMU/RTL cosimulation.
// It observes APB transactions at the testbench boundary and checks the
// register-level behavior expected by the verification environment.
`timescale 1ns/1ps

module uart16550_scoreboard (
  input wire clk,
  input wire reset_n,
  input wire irq
);
  localparam integer SB_OK      = 0;
  localparam integer SB_ERR     = 1;
  localparam integer SB_TIMEOUT = 2;

  localparam [7:0] REG_RBR_THR_DLL = 8'h00;
  localparam [7:0] REG_IER_DLM     = 8'h04;
  localparam [7:0] REG_IIR_FCR     = 8'h08;
  localparam [7:0] REG_LCR         = 8'h0c;
  localparam [7:0] REG_MCR         = 8'h10;
  localparam [7:0] REG_LSR         = 8'h14;
  localparam [7:0] REG_MSR         = 8'h18;
  localparam [7:0] REG_SCR         = 8'h1c;
  localparam [7:0] REG_TX_COUNT    = 8'h20;
  localparam [7:0] REG_RX_COUNT    = 8'h24;
  localparam [7:0] REG_ERR_COUNT   = 8'h28;
  localparam [7:0] REG_IRQ_COUNT   = 8'h2c;

  reg [7:0] ier;
  reg [7:0] lcr;
  reg [7:0] mcr;
  reg [7:0] scr;
  reg [7:0] dll;
  reg [7:0] dlm;
  reg [7:0] exp_rx_fifo [0:255];
  reg [11:0] read_cov;
  reg [11:0] write_cov;

  integer exp_rx_head;
  integer exp_rx_tail;
  integer exp_rx_count;
  integer writes;
  integer reads;
  integer checks;
  integer errors;
  integer tx_count;
  integer rx_count;
  integer err_count;
  integer irq_edges;
  reg irq_d;

  initial begin
    reset_model();
  end

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      irq_d = 1'b0;
      irq_edges = 0;
    end else begin
      if (irq && !irq_d) begin
        irq_edges = irq_edges + 1;
      end
      irq_d = irq;
    end
  end

  task automatic reset_model;
    begin
      ier = 8'h00;
      lcr = 8'h03;
      mcr = 8'h00;
      scr = 8'h00;
      dll = 8'h01;
      dlm = 8'h00;
      exp_rx_head = 0;
      exp_rx_tail = 0;
      exp_rx_count = 0;
      writes = 0;
      reads = 0;
      checks = 0;
      errors = 0;
      tx_count = 0;
      rx_count = 0;
      err_count = 0;
      irq_edges = 0;
      irq_d = 1'b0;
      read_cov = 12'd0;
      write_cov = 12'd0;
    end
  endtask

  function automatic integer reg_index(input [7:0] offset);
    begin
      reg_index = {24'd0, offset} >> 2;
    end
  endfunction

  function automatic integer popcount12(input [11:0] value);
    integer i;
    begin
      popcount12 = 0;
      for (i = 0; i < 12; i = i + 1) begin
        if (value[i]) begin
          popcount12 = popcount12 + 1;
        end
      end
    end
  endfunction

  task automatic cover_read(input [7:0] offset);
    integer idx;
    begin
      idx = reg_index(offset);
      if (idx >= 0 && idx < 12) begin
        read_cov[idx] = 1'b1;
      end
    end
  endtask

  task automatic cover_write(input [7:0] offset);
    integer idx;
    begin
      idx = reg_index(offset);
      if (idx >= 0 && idx < 12) begin
        write_cov[idx] = 1'b1;
      end
    end
  endtask

  task automatic push_expected_rx(input [7:0] value);
    begin
      if (exp_rx_count == 256) begin
        errors = errors + 1;
        err_count = err_count + 1;
        $display("[SCOREBOARD] expected RX queue overflow");
      end else begin
        exp_rx_fifo[exp_rx_tail] = value;
        exp_rx_tail = (exp_rx_tail + 1) % 256;
        exp_rx_count = exp_rx_count + 1;
      end
    end
  endtask

  task automatic pop_expected_rx(output integer has_value,
                                 output [7:0] value);
    begin
      if (exp_rx_count == 0) begin
        has_value = 0;
        value = 8'h00;
      end else begin
        has_value = 1;
        value = exp_rx_fifo[exp_rx_head];
        exp_rx_head = (exp_rx_head + 1) % 256;
        exp_rx_count = exp_rx_count - 1;
      end
    end
  endtask

  task automatic expect8(input integer txn_id,
                         input [7:0] offset,
                         input [7:0] expected,
                         input [7:0] actual,
                         input [127:0] name);
    begin
      checks = checks + 1;
      if (actual !== expected) begin
        errors = errors + 1;
        $display("[SCOREBOARD] txn=%0d %0s mismatch offset=0x%02h expected=0x%02h actual=0x%02h",
                 txn_id, name, offset, expected, actual);
      end
    end
  endtask

  task automatic expect32(input integer txn_id,
                          input [7:0] offset,
                          input integer expected,
                          input longint unsigned actual,
                          input [127:0] name);
    begin
      checks = checks + 1;
      if (actual[31:0] !== expected[31:0]) begin
        errors = errors + 1;
        $display("[SCOREBOARD] txn=%0d %0s mismatch offset=0x%02h expected=%0d actual=%0d",
                 txn_id, name, offset, expected, actual[31:0]);
      end
    end
  endtask

  task automatic observe_write(input integer txn_id,
                               input integer offset_i,
                               input longint unsigned data,
                               input integer size);
    reg [7:0] offset;
    reg [7:0] data8;
    begin
      offset = offset_i[7:0];
      data8 = data[7:0];
      writes = writes + 1;
      cover_write(offset);

      case (offset)
        REG_RBR_THR_DLL: begin
          if (lcr[7]) begin
            dll = data8;
          end else begin
            tx_count = tx_count + 1;
            push_expected_rx(data8);
          end
        end

        REG_IER_DLM: begin
          if (lcr[7]) begin
            dlm = data8;
          end else begin
            ier = data8 & 8'h0f;
          end
        end

        REG_IIR_FCR: begin
          if (data8[2]) begin
            exp_rx_head = 0;
            exp_rx_tail = 0;
            exp_rx_count = 0;
          end
          if (data8[1]) begin
            // TX FIFO flush has no queued software-visible expectation here.
          end
        end

        REG_LCR: lcr = data8;
        REG_MCR: mcr = data8;
        REG_SCR: scr = data8;
        REG_TX_COUNT: tx_count = 0;
        REG_RX_COUNT: rx_count = 0;
        REG_ERR_COUNT: err_count = 0;
        REG_IRQ_COUNT: irq_edges = 0;
        default: begin
          errors = errors + 1;
          $display("[SCOREBOARD] txn=%0d write to unsupported offset=0x%02h size=%0d",
                   txn_id, offset, size);
        end
      endcase
    end
  endtask

  task automatic observe_read(input integer txn_id,
                              input integer offset_i,
                              input longint unsigned actual,
                              input integer size);
    reg [7:0] offset;
    reg [7:0] actual8;
    reg [7:0] expected8;
    integer has_value;
    begin
      offset = offset_i[7:0];
      actual8 = actual[7:0];
      reads = reads + 1;
      cover_read(offset);

      case (offset)
        REG_RBR_THR_DLL: begin
          if (lcr[7]) begin
            expect8(txn_id, offset, dll, actual8, "DLL");
          end else begin
            pop_expected_rx(has_value, expected8);
            if (has_value == 0) begin
              expected8 = 8'h00;
            end else begin
              rx_count = rx_count + 1;
            end
            expect8(txn_id, offset, expected8, actual8, "RBR");
          end
        end

        REG_IER_DLM: begin
          expect8(txn_id, offset, lcr[7] ? dlm : ier, actual8,
                  lcr[7] ? "DLM" : "IER");
        end

        REG_LCR: expect8(txn_id, offset, lcr, actual8, "LCR");
        REG_MCR: expect8(txn_id, offset, {3'b000, mcr[4:0]}, actual8, "MCR");
        REG_MSR: expect8(txn_id, offset, 8'h10, actual8, "MSR");
        REG_SCR: expect8(txn_id, offset, scr, actual8, "SCR");
        REG_TX_COUNT: expect32(txn_id, offset, tx_count, actual, "TX_COUNT");
        REG_RX_COUNT: expect32(txn_id, offset, rx_count, actual, "RX_COUNT");
        REG_ERR_COUNT: expect32(txn_id, offset, err_count, actual, "ERR_COUNT");
        REG_LSR: begin
          checks = checks + 1;
          if (!actual8[5]) begin
            errors = errors + 1;
            $display("[SCOREBOARD] txn=%0d LSR.THRE unexpectedly low: 0x%02h",
                     txn_id, actual8);
          end
        end
        REG_IIR_FCR, REG_IRQ_COUNT: begin
          checks = checks + 1;
        end
        default: begin
          errors = errors + 1;
          $display("[SCOREBOARD] txn=%0d read from unsupported offset=0x%02h size=%0d actual=0x%0h",
                   txn_id, offset, size, actual);
        end
      endcase
    end
  endtask

  task automatic report;
    begin
      $display("[SCOREBOARD] writes=%0d reads=%0d checks=%0d errors=%0d rx_expected_left=%0d",
               writes, reads, checks, errors, exp_rx_count);
      $display("[SCOREBOARD] coverage write_regs=%0d/12 read_regs=%0d/12 irq_edges=%0d",
               popcount12(write_cov), popcount12(read_cov), irq_edges);
      if (errors == 0) begin
        $display("[SCOREBOARD] RESULT=PASS");
      end else begin
        $display("[SCOREBOARD] RESULT=FAIL errors=%0d", errors);
      end
    end
  endtask
endmodule
