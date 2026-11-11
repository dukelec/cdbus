# system clock: pll output, 40 MHz
create_clock -period 25 -name {global_clk} [get_nets {g_clk}]

set_clock_uncertainty -setup -from [get_clocks {global_clk}] -to [get_clocks {global_clk}] 0.200
#set_clock_uncertainty -hold -from [get_clocks {global_clk}] -to [get_clocks {global_clk}] 0.050


# spi clock: 32 MHz
# also the time from the address of a command to the first read data byte, both taken by sck
create_clock -period 31.25 -name {spi_clk} [get_nets {sck}]

set_clock_uncertainty -setup -from [get_clocks {spi_clk}] -to [get_clocks {spi_clk}] 0.200
#set_clock_uncertainty -hold -from [get_clocks {spi_clk}] -to [get_clocks {spi_clk}] 0.050

# io paths are checked only with an input or output delay

# sdi: changed by the host at the falling edge and valid 7 ns later, sampled at the rising edge
set_input_delay -max 7 -clock spi_clk -clock_fall [get_ports {sdi}]

# sdo: sampled by the host at the rising edge, sent at the falling edge before it: 13 ns for this chip,
# which leaves 2.6 ns of the half period to the host, or 15.6 ns more with sdo_early
set_output_delay -max 2.6 -clock spi_clk [get_ports {sdo}]
set_max_delay -to [get_ports {sdo}] 13


# between the two clocks: no fixed phase, the data only has to settle before it is taken
#set_clock_groups -asynchronous -group {global_clk} -group {spi_clk}
# sck to system clock: address and data are taken 2 system clocks (50 ns) after their event at the earliest
set_max_delay -from [get_clocks {spi_clk}] -to [get_clocks {global_clk}] 40
# system clock to sck: read data is loaded 7 sck after its event, up to 4 system clocks of them to fetch it
set_max_delay -from [get_clocks {global_clk}] -to [get_clocks {spi_clk}] 40


# crystal oscillator: limit the delay of the inverter from clk_i to clk_o
#set_max_delay  -from [get_ports {clk_i}]  -to [get_ports {clk_o}] 10.00

create_clock -name vclk -period 10
set_clock_uncertainty -setup 0.3 [get_clocks {vclk}]
set_input_delay -max 0.4 -clock vclk [get_ports {clk_i}]
set_output_delay -max 0.4 -clock vclk [get_ports {clk_o}]

