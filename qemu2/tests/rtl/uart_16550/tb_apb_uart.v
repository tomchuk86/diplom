// Стенд: тот же путь, что на DE1-SoC: Avalon-MM (HPS lw bridge) -> avalon_apb_uart_16550 -> APB UART.
// QEMU/cosim шлёт байтовые смещения MMIO (0x00,0x04,...,0x14,0x20,...) как Linux/драйвер на плате;
// здесь они переводятся в avs_address = byte_off >> 2, как в Platform Designer.
`timescale 1ns/1ps
module tb_apb_uart;
  import "DPI-C" task bridge_init();
  import "DPI-C" context task bridge_poll_once();
  export "DPI-C" task sv_uart_read;
  export "DPI-C" task sv_uart_write;

  reg        pclk, presetn;
  reg [5:0]  avs_address;
  reg        avs_read, avs_write;
  reg [31:0] avs_writedata;
  reg [3:0]  avs_byteenable;
  wire [31:0] avs_readdata;
  wire       avs_waitrequest;
  wire       uart_txd, uart_rxd, uart_irq;

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
    .irq(uart_irq),
    .uart_txd(uart_txd),
    .uart_rxd(uart_rxd)
  );
  assign uart_rxd = uart_txd;
  initial pclk = 0;
  always #5 pclk = ~pclk;

  task wapb (input [7:0] a, input [7:0] d);
    begin
      @(posedge pclk);
      avs_address   = a[7:2];
      avs_writedata = {24'd0, d};
      avs_byteenable = 4'b0001;
      avs_write     = 1'b1;
      avs_read      = 1'b0;
      @(posedge pclk);
      avs_write     = 1'b0;
    end
  endtask

  task rapb (input [7:0] a, output [7:0] d);
    begin
      @(posedge pclk);
      avs_address    = a[7:2];
      avs_read       = 1'b1;
      avs_write      = 1'b0;
      avs_byteenable = 4'b0000;
      @(posedge pclk);
      d = avs_readdata[7:0];
      avs_read = 1'b0;
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

  task sv_uart_write(input int offset, input longint unsigned data, input int size);
    begin
      wapb(offset[7:0], data[7:0]);
      if (offset == 8'h0c)
        dlab_cosim = data[7];
      else if ((offset == 8'h00) && !dlab_cosim)
        repeat (COSIM_POST_THR_CYCLES) @(posedge pclk);
    end
  endtask

  task sv_uart_read(input int offset, input int size, output longint unsigned data);
    reg [7:0] d8;
    begin
      rapb(offset[7:0], d8);
      data = d8;
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
    if (fd) begin
      $fdisplay(fd, "UART self-test: started");
    end
    avs_read = 0;
    avs_write = 0;
    avs_address = 6'd0;
    presetn = 0;
    #40 presetn = 1;

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
      if (fd) begin
        $fdisplay(fd, "RESULT=FAIL RBR= %h", rb);
        $fdisplay(fd, "END");
        $fclose(fd);
      end
    end else begin
      $display("OK:   RBR= %h (loopback 8'hA5)", rb);
      if (fd) begin
        $fdisplay(fd, "RESULT=PASS RBR= %h", rb);
        $fdisplay(fd, "END");
        $fclose(fd);
      end
    end
    $display("*** sim_result.txt обновлён. GTKWave: File -> Open waves_uart.vcd (в папке sim) ***");
    $finish(0);
  end
endmodule
