#!/bin/bash

iverilog -obaud_rate_tb.vvp -tvvp baud_rate_tb.v ../../hdl/baud_rate.v
./baud_rate_tb.vvp

