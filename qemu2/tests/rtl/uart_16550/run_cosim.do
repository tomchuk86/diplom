# COSIM run:
# 1) Builds bridge_dpi.so (TCP server :1234 + uart_cosim_protocol.c)
# 2) Compiles RTL/tb +COSIM (bridge_poll_once обслуживает QEMU)
# 3) После "[BRIDGE] waiting..." запустите QEMU с UART16550_COSIM=1
#
# Usage:
#   cd /home/vboxuser/qemu/tests/rtl/uart_16550
#   vsim -c -do run_cosim.do

if {![file exists bridge_dpi.cpp]} {
  echo "ERROR: bridge_dpi.cpp not found in [pwd]"
  quit -f
}

if {[file exists bridge_dpi.so]} {
  file delete -force bridge_dpi.so
}

if {[file exists work]} {
  file delete -force work
}

echo "Building DPI bridge shared library..."
echo "Building DPI bridge shared library..."
# uart_cosim_protocol.c must compile as *C* (gcc). If g++ compiles a .c file it may treat it as C++
# and mangle symbols → vsim-12005 Undefined uart_cosim_parse_* at runtime.
if {[file exists uart_cosim_protocol_bridge.o]} {
  file delete -force uart_cosim_protocol_bridge.o
}
exec gcc -m32 -fPIC -O2 -I../../../include -c ../../../hw/char/uart_cosim_protocol.c -o uart_cosim_protocol_bridge.o
exec g++ -m32 -shared -fPIC -O2 -I../../../include bridge_dpi.cpp uart_cosim_protocol_bridge.o -o bridge_dpi.so

vlib work
vmap work work
vlog -sv -work work +incdir+../../../rtl/uart_16550 ../../../rtl/uart_16550/uart_baud.v ../../../rtl/uart_16550/uart_fifo.v ../../../rtl/uart_16550/uart_tx.v ../../../rtl/uart_16550/uart_rx.v ../../../rtl/uart_16550/uart_16550_core.v ../../../rtl/uart_16550/apb_uart_16550.v ../../../rtl/uart_16550/avalon_apb_uart_16550.v apb_master_bfm.sv uart16550_scoreboard.sv tb_apb_uart.v

if {[file exists sim_transcript.log]} { file delete -force sim_transcript.log }
transcript file sim_transcript.log
transcript on

echo "Starting cosim testbench (+COSIM, -sv_lib bridge_dpi)..."
vsim -onfinish stop -sv_lib ./bridge_dpi work.tb_apb_uart +COSIM
run -all
