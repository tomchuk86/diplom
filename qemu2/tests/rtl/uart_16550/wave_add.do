# Сигналы для окна Wave (после vsim, до run -all): do wave_add.do
onerror { resume }
add wave -divider "Avalon-MM (как lw bridge на плате)"
add wave -noupdate /tb_apb_uart/pclk
add wave -noupdate /tb_apb_uart/presetn
add wave -hex -noupdate /tb_apb_uart/avs_address
add wave -noupdate /tb_apb_uart/avs_read
add wave -noupdate /tb_apb_uart/avs_write
add wave -hex -noupdate /tb_apb_uart/avs_writedata
add wave -noupdate /tb_apb_uart/avs_byteenable
add wave -hex -noupdate /tb_apb_uart/avs_readdata
add wave -noupdate /tb_apb_uart/avs_waitrequest
add wave -divider "UART / loopback"
add wave -noupdate /tb_apb_uart/uart_txd
add wave -noupdate /tb_apb_uart/uart_rxd
add wave -noupdate /tb_apb_uart/uart_irq
add wave -divider "Core dut.u_uart.u"
add wave -noupdate /tb_apb_uart/dut/u_uart/u/t16
add wave -noupdate /tb_apb_uart/dut/u_uart/u/txd_w
add wave -noupdate /tb_apb_uart/dut/u_uart/u/ubsy
add wave -noupdate /tb_apb_uart/dut/u_uart/u/us
configure wave -namecolwidth 200
echo " wave_add: открой View -> Wave если не видно"
