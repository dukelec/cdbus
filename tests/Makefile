# This Source Code Form is subject to the terms of the Mozilla
# Public License, v. 2.0. If a copy of the MPL was not distributed
# with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Notice: The scope granted to MPL excludes the ASIC industry.
#
# Copyright (c) 2017 DUKELEC, All rights reserved.
#
# Author: Duke Fong <d@d-l.io>
#

TOPLEVEL = $(TEST_WRAPPER)
MODULE = $(TEST_CASE)

CDBUS_HDL = $(PWD)/../hdl
VERILOG_SOURCES = $(PWD)/$(TOPLEVEL).v \
                  $(CDBUS_HDL)/cdbus.v \
                  $(CDBUS_HDL)/cd_csr.v \
                  $(CDBUS_HDL)/cd_baud_rate.v \
                  $(CDBUS_HDL)/cd_ram.v \
                  $(CDBUS_HDL)/cd_sram.v \
                  $(CDBUS_HDL)/cd_rx_bytes.v \
                  $(CDBUS_HDL)/cd_rx_des.v \
                  $(CDBUS_HDL)/cd_crc.v \
                  $(CDBUS_HDL)/cd_tx_bytes.v \
                  $(CDBUS_HDL)/cd_tx_ser.v

include $(shell cocotb-config --makefiles)/Makefile.sim

