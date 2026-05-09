// Стенд: APB-запись в UART, loopback, чтение RBR. Требуется iverilog/ModelSim.
`timescale 1ns/1ps
module tb_apb_uart;
  import "DPI-C" task bridge_init();
  import "DPI-C" context task bridge_poll_once();
  export "DPI-C" task sv_uart_read;
  export "DPI-C" task sv_uart_write;

  reg  pclk, presetn, psel, penable, pwrite;
  reg [7:0]  paddr;
  reg [31:0]  pwdata;
  reg [3:0]  pstrb;
  wire [31:0]  prdata; wire  pready, pslverr,  uart_txd,  uart_rxd,  uart_irq;
  apb_uart_16550 dut ( .pclk(pclk), .presetn(presetn), .psel(psel), .penable(penable), .pwrite(pwrite),
    .paddr(paddr), .pwdata(pwdata), .pstrb(pstrb), .prdata(prdata), .pready(pready), .pslverr(pslverr),
    .uart_txd(uart_txd), .uart_rxd(uart_rxd), .uart_irq(uart_irq) );
  // loopback для приёма своего TX (без mcr.4, чтобы путь rxd=txd)
  assign uart_rxd  = uart_txd;
  initial  pclk  = 0; always  #5 pclk  = ~pclk;
  task wapb (input [7:0] a, input [7:0] d);
    begin
      @(posedge pclk);  psel  = 1; penable  = 0; pwrite  = 1; paddr  = a;  pwdata  = {24'd0, d};  pstrb  = 4'b0001; 
      @(posedge pclk);  penable  = 1;
      @(posedge pclk);  psel  = 0; penable  = 0; 
    end
  endtask
  task rapb (input [7:0] a, output [7:0] d);
    begin
      @(posedge pclk);  psel  = 1; penable  = 0; pwrite  = 0; paddr  = a;  pstrb  = 4'd0; 
      @(posedge pclk);  penable  = 1;
      @(posedge pclk);  d  = prdata[7:0];
      psel  = 0; penable  = 0; 
    end
  endtask

  task sv_uart_write(input int offset, input longint unsigned data, input int size);
    begin
      wapb(offset[7:0], data[7:0]);
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
  // VCD для GTKWave: только ядро dut.u (uart_16550_core и ниже) — не весь tb (иначе сотни МБ).
`ifndef NO_VCD
  initial begin
    $dumpfile("waves_uart.vcd");
    $dumpvars(0, dut.u);
  end
`endif
  initial begin
    cosim_mode = $test$plusargs("COSIM");
    $display("*** tb_apb_uart: старт (результат -> sim/ sim_result.txt) ***");
    fd = $fopen("sim_result.txt");
    if (fd) begin
      $fdisplay(fd, "UART self-test: started");
    end
    presetn  = 0; psel  = 0; penable  = 0; #40  presetn  = 1;

    if (cosim_mode) begin
      $display("*** COSIM mode enabled: waiting QEMU transactions via DPI bridge ***");
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
