# COSIM run:
# 1) Builds DPI bridge shared library (bridge_dpi.so)
# 2) Compiles RTL/tb with SystemVerilog DPI enabled
# 3) Starts simulation with +COSIM and waits for QEMU socket client
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
exec g++ -m32 -shared -fPIC -O2 bridge_dpi.cpp -o bridge_dpi.so

vlib work
vmap work work
vlog -sv -work work +incdir+../../../rtl/uart_16550 ../../../rtl/uart_16550/uart_baud.v ../../../rtl/uart_16550/uart_fifo.v ../../../rtl/uart_16550/uart_tx.v ../../../rtl/uart_16550/uart_rx.v ../../../rtl/uart_16550/uart_16550_core.v ../../../rtl/uart_16550/apb_uart_16550.v tb_apb_uart.v

if {[file exists sim_transcript.log]} { file delete -force sim_transcript.log }
transcript file sim_transcript.log
transcript on

echo "Starting cosim testbench (+COSIM, -sv_lib bridge_dpi)..."
vsim -onfinish stop -sv_lib ./bridge_dpi work.tb_apb_uart +COSIM
run -all
