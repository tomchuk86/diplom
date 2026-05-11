// Simple Avalon-MM/APB-facing master BFM used by the QEMU cosimulation bridge.
// The DUT wrapper has zero wait states, but the BFM still implements timeouts
// so protocol errors show up as explicit TIMEOUT responses instead of hangs.
`timescale 1ns/1ps

module apb_master_bfm #(
  parameter ADDR_W = 6,
  parameter DEFAULT_TIMEOUT = 100000
) (
  input  wire              clk,
  input  wire              reset_n,

  output reg [ADDR_W-1:0]  avs_address,
  output reg               avs_read,
  output reg               avs_write,
  output reg [31:0]        avs_writedata,
  output reg [3:0]         avs_byteenable,
  input  wire [31:0]       avs_readdata,
  input  wire              avs_waitrequest,
  input  wire              irq
);
  localparam integer BFM_OK      = 0;
  localparam integer BFM_ERR     = 1;
  localparam integer BFM_TIMEOUT = 2;

  integer accesses;
  integer reads;
  integer writes;
  integer timeout_errors;

  initial begin
    init();
  end

  task automatic init;
    begin
      avs_address    = {ADDR_W{1'b0}};
      avs_read       = 1'b0;
      avs_write      = 1'b0;
      avs_writedata  = 32'd0;
      avs_byteenable = 4'd0;
      accesses       = 0;
      reads          = 0;
      writes         = 0;
      timeout_errors = 0;
    end
  endtask

  task automatic idle_bus;
    begin
      avs_read       = 1'b0;
      avs_write      = 1'b0;
      avs_writedata  = 32'd0;
      avs_byteenable = 4'd0;
    end
  endtask

  task automatic wait_reset_done;
    begin
      while (!reset_n) begin
        @(posedge clk);
      end
    end
  endtask

  function automatic [3:0] byteenable_for_size(input integer size);
    begin
      case (size)
        1: byteenable_for_size = 4'b0001;
        2: byteenable_for_size = 4'b0011;
        4: byteenable_for_size = 4'b1111;
        default: byteenable_for_size = 4'b0000;
      endcase
    end
  endfunction

  task automatic wait_ready(input integer timeout_cycles,
                            output integer status);
    integer i;
    begin
      status = BFM_TIMEOUT;
      if (timeout_cycles <= 0) begin
        timeout_cycles = DEFAULT_TIMEOUT;
      end

      for (i = 0; i < timeout_cycles; i = i + 1) begin
        #1;
        if (!avs_waitrequest) begin
          status = BFM_OK;
          i = timeout_cycles;
        end else begin
          @(posedge clk);
        end
      end

      if (status == BFM_TIMEOUT) begin
        timeout_errors = timeout_errors + 1;
      end
    end
  endtask

  task automatic write_access(input [7:0] byte_offset,
                              input [31:0] data,
                              input integer size,
                              input integer timeout_cycles,
                              output integer status);
    begin
      if (byteenable_for_size(size) == 4'b0000) begin
        status = BFM_ERR;
        $display("[APB_BFM] unsupported write size=%0d offset=0x%02h",
                 size, byte_offset);
      end else begin
        wait_reset_done();
        @(posedge clk);
        avs_address    = byte_offset[7:2];
        avs_writedata  = data;
        avs_byteenable = byteenable_for_size(size);
        avs_write      = 1'b1;
        avs_read       = 1'b0;

        wait_ready(timeout_cycles, status);
        @(posedge clk);
        idle_bus();

        accesses = accesses + 1;
        writes = writes + 1;
      end
    end
  endtask

  task automatic read_access(input [7:0] byte_offset,
                             output [31:0] data,
                             input integer size,
                             input integer timeout_cycles,
                             output integer status);
    begin
      data = 32'd0;
      if (byteenable_for_size(size) == 4'b0000) begin
        status = BFM_ERR;
        $display("[APB_BFM] unsupported read size=%0d offset=0x%02h",
                 size, byte_offset);
      end else begin
        wait_reset_done();
        @(posedge clk);
        avs_address    = byte_offset[7:2];
        avs_read       = 1'b1;
        avs_write      = 1'b0;
        avs_writedata  = 32'd0;
        avs_byteenable = 4'b0000;

        wait_ready(timeout_cycles, status);
        #1;
        data = avs_readdata;
        @(posedge clk);
        idle_bus();

        accesses = accesses + 1;
        reads = reads + 1;
      end
    end
  endtask

  task automatic write8(input [7:0] byte_offset,
                        input [7:0] data,
                        input integer timeout_cycles,
                        output integer status);
    begin
      write_access(byte_offset, {24'd0, data}, 1, timeout_cycles, status);
    end
  endtask

  task automatic read8(input [7:0] byte_offset,
                       output [7:0] data,
                       input integer timeout_cycles,
                       output integer status);
    reg [31:0] data32;
    begin
      read_access(byte_offset, data32, 1, timeout_cycles, status);
      data = data32[7:0];
    end
  endtask

  task automatic check8(input [7:0] byte_offset,
                        input [7:0] expected,
                        input integer timeout_cycles,
                        output integer status);
    reg [7:0] actual;
    begin
      read8(byte_offset, actual, timeout_cycles, status);
      if (status == BFM_OK && actual !== expected) begin
        status = BFM_ERR;
        $display("[APB_BFM] CHECK mismatch offset=0x%02h expected=0x%02h actual=0x%02h",
                 byte_offset, expected, actual);
      end
    end
  endtask

  task automatic wait_irq(input integer timeout_cycles,
                          output integer status);
    integer i;
    begin
      status = BFM_TIMEOUT;
      if (timeout_cycles <= 0) begin
        timeout_cycles = DEFAULT_TIMEOUT;
      end

      for (i = 0; i < timeout_cycles; i = i + 1) begin
        @(posedge clk);
        if (irq) begin
          status = BFM_OK;
          i = timeout_cycles;
        end
      end

      if (status == BFM_TIMEOUT) begin
        timeout_errors = timeout_errors + 1;
      end
    end
  endtask

  task automatic report;
    begin
      $display("[APB_BFM] accesses=%0d reads=%0d writes=%0d timeouts=%0d",
               accesses, reads, writes, timeout_errors);
    end
  endtask
endmodule
