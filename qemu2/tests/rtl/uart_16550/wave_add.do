# Сигналы для окна Wave (после vsim, до run -all): do wave_add.do
onerror { resume }
add wave -divider "APB"
add wave -noupdate /tb_apb_uart/pclk
add wave -noupdate /tb_apb_uart/presetn
add wave -noupdate /tb_apb_uart/psel
add wave -noupdate /tb_apb_uart/penable
add wave -noupdate /tb_apb_uart/pwrite
add wave -hex -noupdate /tb_apb_uart/paddr
add wave -hex -noupdate /tb_apb_uart/pwdata
add wave -hex -noupdate /tb_apb_uart/prdata
add wave -noupdate /tb_apb_uart/pstrb
add wave -divider "UART / loopback"
add wave -noupdate /tb_apb_uart/uart_txd
add wave -noupdate /tb_apb_uart/uart_rxd
add wave -noupdate /tb_apb_uart/uart_irq
add wave -divider "Core dut.u"
add wave -noupdate /tb_apb_uart/dut/u/t16
add wave -noupdate /tb_apb_uart/dut/u/txd_w
add wave -noupdate /tb_apb_uart/dut/u/ubsy
add wave -noupdate /tb_apb_uart/dut/u/us
configure wave -namecolwidth 200
echo " wave_add: открой View -> Wave если не видно"
