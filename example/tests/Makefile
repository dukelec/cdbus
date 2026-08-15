# This Source Code Form is subject to the terms of the CERN Open
# Hardware Licence Version 2 - Strongly Reciprocal (CERN-OHL-S v2):
# https://ohwr.org/cern_ohl_s_v2.txt (see the LICENSE file).
# Notice: The CDBUS Exception (see the LICENSE_EXCEPTION file)
# grants free commercial use in FPGAs and other programmable logic
# devices; it does not extend to ASIC design or manufacturing.
#
# Copyright (c) 2017-2026 DUKELEC, All rights reserved.
#
# Author: Duke Fong <d@d-l.io>
#

TOPLEVEL = $(TEST_WRAPPER)
COCOTB_TEST_MODULES = $(TEST_CASE)

CDCTL_HDL = $(PWD)/..
CDBUS_HDL = $(PWD)/../../hdl
VERILOG_SOURCES = $(PWD)/$(TOPLEVEL).v \
                  $(CDCTL_HDL)/top_spi/cdctl_spi.v \
                  $(CDCTL_HDL)/common/spi_slave.v \
                  $(CDCTL_HDL)/top_qspi/cdctl_qspi.v \
                  $(CDCTL_HDL)/common/qspi_slave.v \
                  $(CDCTL_HDL)/top_i2c/cdctl_i2c.v \
                  $(CDCTL_HDL)/common/i2c_slave.v \
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

