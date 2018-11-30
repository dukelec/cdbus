#!/bin/bash

iverilog -obaud_rate_gen_tb.vvp -tvvp baud_rate_gen_tb.v ../../hdl/baud_rate_gen.v
./baud_rate_gen_tb.vvp

