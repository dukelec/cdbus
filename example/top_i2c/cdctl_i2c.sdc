# Constrain clock port clk with a 42-ns requirement (24MHz)
# 12.288: 81ns
# 111.111: 9ns


create_clock -period 25 -name {global_clk} [get_nets {g_clk}]

set_clock_uncertainty -setup -from [get_clocks {global_clk}] -to [get_clocks {global_clk}] 0.200
#set_clock_uncertainty -hold -from [get_clocks {global_clk}] -to [get_clocks {global_clk}] 0.050


#set_max_delay  -from [get_ports {clk_i}]  -to [get_ports {clk_o}] 10.00

create_clock -name vclk -period 10
set_clock_uncertainty -setup 0.3 [get_clocks {vclk}]
set_input_delay -max 0.4 -clock vclk [get_ports {clk_i}]
set_output_delay -max 0.4 -clock vclk [get_ports {clk_o}]
