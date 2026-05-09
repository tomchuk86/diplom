package require -exact qsys 13.1

create_system soc_system
set_project_property DEVICE_FAMILY "Cyclone V"
set_project_property DEVICE 5CSEMA5F31C6

add_instance clk_0 altera_clock_bridge
set_instance_parameter_value clk_0 EXPLICIT_CLOCK_RATE 50000000

add_instance hps_0 altera_hps
set_instance_parameter_value hps_0 F2S_Width 0
set_instance_parameter_value hps_0 S2F_Width 0
set_instance_parameter_value hps_0 LWH2F_Enable true
set_instance_parameter_value hps_0 F2SINTERRUPT_Enable 0
set_instance_parameter_value hps_0 MPU_EVENTS_Enable 0

add_instance uart_0 uart16550_avalon

add_connection clk_0.out_clk hps_0.h2f_lw_axi_clock
add_connection clk_0.out_clk hps_0.f2h_sdram0_clock
add_connection clk_0.out_clk uart_0.clock
add_connection hps_0.h2f_reset uart_0.reset
add_connection hps_0.h2f_lw_axi_master uart_0.avalon_slave
set_connection_parameter_value hps_0.h2f_lw_axi_master/uart_0.avalon_slave baseAddress 0x00010000

add_interface clk clock end
set_interface_property clk EXPORT_OF clk_0.in_clk

add_interface uart conduit end
set_interface_property uart EXPORT_OF uart_0.uart

save_system soc_system.qsys
