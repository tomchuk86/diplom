# В Transcript (ModelSim): cd в tests/rtl/uart_16550, затем: do compile.do
vlib work
vmap work work
vlog -sv -work work +incdir+../../../rtl/uart_16550 ../../../rtl/uart_16550/uart_baud.v ../../../rtl/uart_16550/uart_fifo.v ../../../rtl/uart_16550/uart_tx.v ../../../rtl/uart_16550/uart_rx.v ../../../rtl/uart_16550/uart_16550_core.v ../../../rtl/uart_16550/apb_uart_16550.v ../../../rtl/uart_16550/avalon_apb_uart_16550.v apb_master_bfm.sv uart16550_scoreboard.sv tb_apb_uart.v
echo "OK. Запуск: do run.do"
