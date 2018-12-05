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
                  $(CDBUS_HDL)/cd_csr.v \
                  $(CDBUS_HDL)/cd_baud_rate.v \
                  $(CDBUS_HDL)/cd_ram.v \
                  $(CDBUS_HDL)/cd_rx_bytes.v \
                  $(CDBUS_HDL)/cd_rx_des.v \
                  $(CDBUS_HDL)/cd_crc.v \
                  $(CDBUS_HDL)/cd_tx_bytes.v \
                  $(CDBUS_HDL)/cd_tx_ser.v

TOPLEVEL = cdbus_wrapper
MODULE = test_cdbus
include $(COCOTB)/makefiles/Makefile.inc
include $(COCOTB)/makefiles/Makefile.sim

