// Стенд: тот же путь, что на DE1-SoC: Avalon-MM (HPS lw bridge) -> avalon_apb_uart_16550 -> APB UART.
// QEMU/cosim шлёт байтовые смещения MMIO (0x00,0x04,...,0x14,0x20,...) как Linux/драйвер на плате;
// здесь они переводятся в avs_address = byte_off >> 2, как в Platform Designer.
`timescale 1ns/1ps
module tb_apb_uart;
  import "DPI-C" task bridge_init();
  import "DPI-C" context task bridge_poll_once();
  export "DPI-C" task sv_uart_read;
  export "DPI-C" task sv_uart_write;
  export "DPI-C" task sv_uart_read_txn;
  export "DPI-C" task sv_uart_write_txn;
  export "DPI-C" task sv_bridge_reset;

  reg        pclk, presetn;
  wire [5:0]  avs_address;
  wire        avs_read, avs_write;
  wire [31:0] avs_writedata;
  wire [3:0]  avs_byteenable;
  wire [31:0] avs_readdata;
  wire       avs_waitrequest;
  wire       uart_txd, uart_rxd, uart_irq, uart_pslverr;

  apb_master_bfm apb_bfm (
    .clk(pclk),
    .reset_n(presetn),
    .avs_address(avs_address),
    .avs_read(avs_read),
    .avs_write(avs_write),
    .avs_writedata(avs_writedata),
    .avs_byteenable(avs_byteenable),
    .avs_readdata(avs_readdata),
    .avs_waitrequest(avs_waitrequest),
    .irq(uart_irq)
  );

  uart16550_scoreboard sb (
    .clk(pclk),
    .reset_n(presetn),
    .irq(uart_irq)
  );

  avalon_apb_uart_16550 dut (
    .clk(pclk),
    .reset_n(presetn),
    .avs_address(avs_address),
    .avs_read(avs_read),
    .avs_write(avs_write),
    .avs_writedata(avs_writedata),
    .avs_byteenable(avs_byteenable),
    .avs_readdata(avs_readdata),
    .avs_waitrequest(avs_waitrequest),
    .uart_pslverr(uart_pslverr),
    .irq(uart_irq),
    .uart_txd(uart_txd),
    .uart_rxd(uart_rxd)
  );
  assign uart_rxd = uart_txd;
  initial pclk = 0;
  always #5 pclk = ~pclk;

  localparam integer COSIM_STATUS_OK      = 0;
  localparam integer COSIM_STATUS_ERR     = 1;
  localparam integer COSIM_STATUS_TIMEOUT = 2;
  localparam integer DEFAULT_TXN_TIMEOUT  = 100000;

  task wapb (input [7:0] a, input [7:0] d);
    integer status;
    begin
      apb_bfm.write8(a, d, DEFAULT_TXN_TIMEOUT, status);
      if (status == COSIM_STATUS_OK)
        sb.observe_write(0, {24'd0, a}, {56'd0, d}, 1);
      else
        $display("FAIL: APB write timeout/status=%0d offset=0x%02h", status, a);
    end
  endtask

  task rapb (input [7:0] a, output [7:0] d);
    integer status;
    begin
      apb_bfm.read8(a, d, DEFAULT_TXN_TIMEOUT, status);
      if (status == COSIM_STATUS_OK)
        sb.observe_read(0, {24'd0, a}, {56'd0, d}, 1);
      else
        $display("FAIL: APB read timeout/status=%0d offset=0x%02h", status, a);
    end
  endtask

  /*
   * QEMU cosim (UART16550_COSIM=1): TCP -> bridge_poll_once на каждом posedge pclk.
   * sv_uart_* выполняют короткие APB-трансферы и могут ждать @(posedge pclk).
   * Пока транзакция не закончилась, повторный вход в bridge_poll_once блокируется
   * в bridge_dpi.cpp (in_bridge_poll), иначе — параллельный recv/APB и зависание.
   * После записи в THR (не DLAB) даём такты на серийный loopback.
   * 65536 очень медленно при QEMU↔RTL cosim; 1024 обычно хватает для приёмника offline.
   */
  localparam integer COSIM_POST_THR_CYCLES = 1024;
  reg dlab_cosim;

  initial dlab_cosim = 1'b0;

  task sv_uart_write_txn(input int txn_id, input int offset,
                         input longint unsigned data, input int size,
                         input int timeout_cycles,
                         output int status);
    begin
      if ((size != 1) && (size != 2) && (size != 4)) begin
        status = COSIM_STATUS_ERR;
      end else begin
        apb_bfm.write_access(offset[7:0], data[31:0], size,
                             timeout_cycles, status);
        if (status == COSIM_STATUS_OK) begin
          sb.observe_write(txn_id, offset, data, size);
          if (offset == 32'h0000000c)
            dlab_cosim = data[7];
          else if ((offset == 32'h00000000) && !dlab_cosim)
            repeat (COSIM_POST_THR_CYCLES) @(posedge pclk);
        end
      end
    end
  endtask

  task sv_uart_read_txn(input int txn_id, input int offset, input int size,
                        input int timeout_cycles,
                        output longint unsigned data, output int status);
    reg [31:0] d32;
    begin
      data = 0;
      if ((size != 1) && (size != 2) && (size != 4)) begin
        status = COSIM_STATUS_ERR;
      end else begin
        apb_bfm.read_access(offset[7:0], d32, size, timeout_cycles, status);
        data = {32'd0, d32};
        if (status == COSIM_STATUS_OK)
          sb.observe_read(txn_id, offset, data, size);
      end
    end
  endtask

  task sv_uart_write(input int offset, input longint unsigned data, input int size);
    integer status;
    begin
      sv_uart_write_txn(0, offset, data, size, DEFAULT_TXN_TIMEOUT, status);
    end
  endtask

  task sv_uart_read(input int offset, input int size, output longint unsigned data);
    integer status;
    begin
      sv_uart_read_txn(0, offset, size, DEFAULT_TXN_TIMEOUT, data, status);
    end
  endtask

  task sv_bridge_reset;
    begin
      apb_bfm.idle_bus();
      presetn = 1'b0;
      repeat (5) @(posedge pclk);
      presetn = 1'b1;
      repeat (2) @(posedge pclk);
      dlab_cosim = 1'b0;
      sb.reset_model();
    end
  endtask

  reg [7:0]  rb, ls;
  integer  k, fd;
  reg cosim_mode;
  // VCD для GTKWave: только ядро dut.u_uart.u (uart_16550_core и ниже) — не весь tb.
`ifndef NO_VCD
  initial begin
    $dumpfile("waves_uart.vcd");
    $dumpvars(0, dut.u_uart.u);
  end
`endif
  initial begin
    cosim_mode = $test$plusargs("COSIM");
    $display("*** tb_apb_uart: старт (результат -> sim/ sim_result.txt) ***");
    fd = $fopen("sim_result.txt");
    if (fd != 0) begin
      $fdisplay(fd, "UART self-test: started");
    end
    apb_bfm.init();
    sb.reset_model();
    presetn = 0;
    #40 presetn = 1;
    repeat (2) @(posedge pclk);
    sb.reset_model();

    if (cosim_mode) begin
      $display("*** COSIM: TCP bridge -> DPI -> Avalon (как на плате) -> APB UART RTL (QEMU: UART16550_COSIM=1) ***");
      bridge_init();
      forever begin
        @(posedge pclk);
        bridge_poll_once();
      end
    end

    wapb(12, 8'h80);  // LCR: DLAB=1
    wapb(0, 8'h04);  // DLL
    wapb(4, 8'h00);  // DLH
    wapb(12, 8'h03);  // LCR: 8N1, DLAB=0
    wapb(8, 8'h00);  // FCR
    wapb(16, 8'h00); // MCR
    wapb(0, 8'hA5);  // THR
    for (k  = 0; k  < 50000; k  = k + 1)  @(posedge pclk);
    rapb(20, ls);   // LSR, offset 0x14
    rapb(0, rb);    // RBR
    if (rb  !== 8'hA5)  begin
      $display("FAIL: RBR= %h (expected A5)", rb);
      if (fd != 0) begin
        $fdisplay(fd, "RESULT=FAIL RBR= %h", rb);
        $fdisplay(fd, "END");
        $fclose(fd);
      end
    end else begin
      $display("OK:   RBR= %h (loopback 8'hA5)", rb);
      if (fd != 0) begin
        $fdisplay(fd, "RESULT=PASS RBR= %h", rb);
        $fdisplay(fd, "END");
        $fclose(fd);
      end
    end
    apb_bfm.report();
    sb.report();
    $display("*** sim_result.txt обновлён. GTKWave: File -> Open waves_uart.vcd (в папке sim) ***");
    $finish(0);
  end
endmodule
