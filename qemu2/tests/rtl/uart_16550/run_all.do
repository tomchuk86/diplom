# Все в одном (консольный режим, без лишнего кликания):
#   cd /home/vboxuser/qemu/tests/rtl/uart_16550
#   C:\path\to\vsim.exe -c -do run_all.do
# в конце: sim_result.txt, sim_transcript.log, waves_uart.vcd (для GTKWave; окно -c сразу закрывается — это норма)

vlib work
vmap work work
vlog -sv -work work +incdir+../../../rtl/uart_16550 ../../../rtl/uart_16550/uart_baud.v ../../../rtl/uart_16550/uart_fifo.v ../../../rtl/uart_16550/uart_tx.v ../../../rtl/uart_16550/uart_rx.v ../../../rtl/uart_16550/uart_sync_2ff.v ../../../rtl/uart_16550/uart_16550_csr_decode.v ../../../rtl/uart_16550/uart_16550_modem.v ../../../rtl/uart_16550/uart_16550_line_hist.v ../../../rtl/uart_16550/uart_16550_rx_aux.v ../../../rtl/uart_16550/uart_16550_dma_port.v ../../../rtl/uart_16550/uart_16550_mmio_bucket.v ../../../rtl/uart_16550/uart_16550_core.v ../../../rtl/uart_16550/apb_uart_16550.v ../../../rtl/uart_16550/avalon_apb_uart_16550.v apb_master_bfm.sv uart16550_scoreboard.sv tb_apb_uart.v
if {![file exists tb_apb_uart.v]} {
  echo "Предупреждение: запускайте из каталога tests/rtl/uart_16550 (нужен tb_apb_uart.v)."
}
if {[file exists sim_transcript.log]} { file delete -force sim_transcript.log }
transcript file sim_transcript.log
transcript on
echo "PWD=[pwd]  -> sim_result.txt sim_transcript.log"
vsim -onfinish exit work.tb_apb_uart
onbreak {resume}
run -all
quit -f
