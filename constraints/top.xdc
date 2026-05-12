## top.xdc
## Pin constraints for the Basys 3 board (Artix-7 XC7A35T-1CPG236C).
## Adjust USB-UART pin assignments if your board revision differs.

# -------------------------------------------------------------------------
# System clock – 100 MHz onboard oscillator
# -------------------------------------------------------------------------
set_property PACKAGE_PIN W5  [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

# -------------------------------------------------------------------------
# Reset – centre push-button (BTNC, active-high)
# -------------------------------------------------------------------------
set_property PACKAGE_PIN T18 [get_ports rst]
set_property IOSTANDARD  LVCMOS33 [get_ports rst]

# -------------------------------------------------------------------------
# USB-UART interface (CP2104 bridge on Basys 3)
#   uart_rx – serial data arriving at the FPGA from the PC
#   uart_tx – serial data sent from the FPGA to the PC
# -------------------------------------------------------------------------
set_property PACKAGE_PIN B16 [get_ports uart_rx]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_rx]

set_property PACKAGE_PIN A16 [get_ports uart_tx]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_tx]
