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

CDCTL_HDL = $(PWD)/..
CDBUS_HDL = $(PWD)/../../hdl
VERILOG_SOURCES = $(PWD)/$(TOPLEVEL).v \
                  $(CDCTL_HDL)/top_spi/cdctl_spi.v \
                  $(CDCTL_HDL)/common/spi_slave.v \
                  $(CDCTL_HDL)/top_qspi/cdctl_qspi.v \
                  $(CDCTL_HDL)/common/qspi_slave.v \
                  $(PWD)/cdctl_pll_sim.v \
                  $(CDBUS_HDL)/cdbus.v \
                  $(CDBUS_HDL)/cd_csr.v \
                  $(CDBUS_HDL)/cd_baud_rate.v \
                  $(CDBUS_HDL)/cd_tx_ram.v \
                  $(CDBUS_HDL)/cd_rx_ram.v \
                  $(CDBUS_HDL)/lib/cd_spram.v \
                  $(CDBUS_HDL)/lib/cd_sdpram.v \
                  $(CDBUS_HDL)/cd_rx_bytes.v \
                  $(CDBUS_HDL)/cd_rx_des.v \
                  $(CDBUS_HDL)/cd_crc.v \
                  $(CDBUS_HDL)/cd_tx_bytes.v \
                  $(CDBUS_HDL)/cd_tx_ser.v

include $(shell cocotb-config --makefiles)/Makefile.sim

