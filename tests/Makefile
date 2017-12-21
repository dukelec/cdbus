# This Source Code Form is subject to the terms of the Mozilla
# Public License, v. 2.0. If a copy of the MPL was not distributed
# with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Notice: The scope granted to MPL excludes the ASIC industry.
#
# Copyright (c) 2017 DUKELEC, All rights reserved.
#
# Author: Duke Fong <duke@dukelec.com>
#

CDBUS_HDL = $(PWD)/../hdl
VERILOG_SOURCES = $(PWD)/cdbus_wrapper.v \
                  $(CDBUS_HDL)/cdbus.v \
                  $(CDBUS_HDL)/pp_ram.v \
                  $(CDBUS_HDL)/rx_bytes.v \
                  $(CDBUS_HDL)/rx_ser.v \
                  $(CDBUS_HDL)/serial_crc.v \
                  $(CDBUS_HDL)/tx_bytes_des.v

TOPLEVEL = cdbus_wrapper
MODULE = test_cdbus
include $(COCOTB)/makefiles/Makefile.inc
include $(COCOTB)/makefiles/Makefile.sim

