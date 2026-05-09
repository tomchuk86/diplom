package require -exact qsys 13.1

set_module_property NAME uart16550_avalon
set_module_property DISPLAY_NAME "UART16550 Avalon-MM APB bridge"
set_module_property VERSION 1.0
set_module_property GROUP "Diplom"
set_module_property DESCRIPTION "Avalon-MM slave wrapper around the APB UART16550 RTL block"
set_module_property AUTHOR "diplom"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE false
set_module_property ANALYZE_HDL false

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL avalon_apb_uart_16550
add_fileset_file ../../../../../rtl/uart_16550/avalon_apb_uart_16550.v VERILOG PATH ../../../../../rtl/uart_16550/avalon_apb_uart_16550.v TOP_LEVEL_FILE
add_fileset_file ../../../../../rtl/uart_16550/apb_uart_16550.v VERILOG PATH ../../../../../rtl/uart_16550/apb_uart_16550.v
add_fileset_file ../../../../../rtl/uart_16550/uart_16550_core.v VERILOG PATH ../../../../../rtl/uart_16550/uart_16550_core.v
add_fileset_file ../../../../../rtl/uart_16550/uart_baud.v VERILOG PATH ../../../../../rtl/uart_16550/uart_baud.v
add_fileset_file ../../../../../rtl/uart_16550/uart_fifo.v VERILOG PATH ../../../../../rtl/uart_16550/uart_fifo.v
add_fileset_file ../../../../../rtl/uart_16550/uart_rx.v VERILOG PATH ../../../../../rtl/uart_16550/uart_rx.v
add_fileset_file ../../../../../rtl/uart_16550/uart_tx.v VERILOG PATH ../../../../../rtl/uart_16550/uart_tx.v

add_parameter ADDR_W INTEGER 6
set_parameter_property ADDR_W DEFAULT_VALUE 6
set_parameter_property ADDR_W HDL_PARAMETER true
set_parameter_property ADDR_W VISIBLE false

add_interface clock clock end
set_interface_property clock ENABLED true
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
set_interface_property reset ENABLED true
add_interface_port reset reset_n reset_n Input 1

add_interface avalon_slave avalon end
set_interface_property avalon_slave addressUnits WORDS
set_interface_property avalon_slave associatedClock clock
set_interface_property avalon_slave associatedReset reset
set_interface_property avalon_slave bitsPerSymbol 8
set_interface_property avalon_slave burstOnBurstBoundariesOnly false
set_interface_property avalon_slave explicitAddressSpan 256
set_interface_property avalon_slave holdTime 0
set_interface_property avalon_slave isMemoryDevice false
set_interface_property avalon_slave isNonVolatileStorage false
set_interface_property avalon_slave linewrapBursts false
set_interface_property avalon_slave maximumPendingReadTransactions 0
set_interface_property avalon_slave printableDevice false
set_interface_property avalon_slave readLatency 0
set_interface_property avalon_slave readWaitTime 0
set_interface_property avalon_slave setupTime 0
set_interface_property avalon_slave timingUnits Cycles
set_interface_property avalon_slave writeWaitTime 0
set_interface_property avalon_slave ENABLED true
add_interface_port avalon_slave avs_address address Input 6
add_interface_port avalon_slave avs_read read Input 1
add_interface_port avalon_slave avs_write write Input 1
add_interface_port avalon_slave avs_writedata writedata Input 32
add_interface_port avalon_slave avs_byteenable byteenable Input 4
add_interface_port avalon_slave avs_readdata readdata Output 32
add_interface_port avalon_slave avs_waitrequest waitrequest Output 1

add_interface interrupt_sender interrupt end
set_interface_property interrupt_sender associatedAddressablePoint avalon_slave
set_interface_property interrupt_sender associatedClock clock
set_interface_property interrupt_sender associatedReset reset
set_interface_property interrupt_sender ENABLED true
add_interface_port interrupt_sender irq irq Output 1

add_interface uart conduit end
set_interface_property uart associatedClock clock
set_interface_property uart associatedReset reset
set_interface_property uart ENABLED true
add_interface_port uart uart_txd export Output 1
add_interface_port uart uart_rxd export Input 1
