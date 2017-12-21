# This Source Code Form is subject to the terms of the Mozilla
# Public License, v. 2.0. If a copy of the MPL was not distributed
# with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Notice: The scope granted to MPL excludes the ASIC industry.
#
# Copyright (c) 2017 DUKELEC, All rights reserved.
#
# Author: Duke Fong <duke@dukelec.com>
#

import cocotb
from cocotb.binary import BinaryValue
from cocotb.triggers import RisingEdge, ReadOnly, Timer
from cocotb.clock import Clock
from cocotb.drivers.avalon import AvalonMaster
from cocotb.result import ReturnValue, TestFailure


REG_VERSION       = 0x00
REG_SETTING       = 0x01
REG_IDLE_LEN      = 0x02
REG_TX_PERMIT_LEN = 0x03
REG_FILTER        = 0x04
REG_PERIOD_LS_L   = 0x05
REG_PERIOD_LS_H   = 0x06
REG_PERIOD_HS_L   = 0x07
REG_PERIOD_HS_H   = 0x08
REG_INT_FLAG      = 0x09
REG_INT_MASK      = 0x0a
REG_RX            = 0x0b
REG_TX            = 0x0c
REG_RX_CTRL       = 0x0d
REG_TX_CTRL       = 0x0e
REG_RX_ADDR       = 0x0f
REG_RX_PAGE_FLAG  = 0x10


@cocotb.coroutine
def reset(dut, duration=10000):
    dut._log.debug("Resetting DUT")
    dut.reset_n = 0
    yield Timer(duration)
    yield RisingEdge(dut.clk)
    dut.reset_n = 1
    dut._log.debug("Out of reset")

@cocotb.coroutine
def csr_read(dut, address, burst = False):
    yield RisingEdge(dut.clk)
    dut.csr_address = address
    dut.csr_read = 1
    yield ReadOnly()
    data = dut.csr_readdata.value
    
    if not burst:
        yield RisingEdge(dut.clk)
        dut.csr_read = 0
        dut.csr_address = BinaryValue("x" * len(dut.csr_address))
    
    raise ReturnValue(data)

@cocotb.coroutine
def csr_write(dut, address, data, burst = False):
    yield RisingEdge(dut.clk)
    dut.csr_address = address
    dut.csr_writedata = data
    dut.csr_write = 1
    
    if not burst:
        yield RisingEdge(dut.clk)
        dut.csr_write = 0
        dut.csr_address = BinaryValue("x" * len(dut.csr_address))
        dut.csr_writedata = BinaryValue("x" * len(dut.csr_writedata))


@cocotb.test()
def test_cdbus(dut):
    """
    test_cdbus
    """
    dut._log.info("test_cdbus start.")
    
    cocotb.fork(Clock(dut.clk, 5000).start())
    yield reset(dut)
    
    #master = AvalonMaster(dut, "csr", dut.clk)
    
    value = yield csr_read(dut, REG_VERSION, True)
    dut._log.info("REG_VERSION: 0x%02x" % int(value))
    value = yield csr_read(dut, REG_SETTING)
    dut._log.info("REG_SETTING: 0x%02x" % int(value))
    
    yield csr_write(dut, REG_SETTING, BinaryValue("00010001"))
    
    yield csr_write(dut, REG_PERIOD_LS_H, 0, True)
    yield csr_write(dut, REG_PERIOD_LS_L, 27, True)
    yield csr_write(dut, REG_PERIOD_HS_H, 0, True)
    yield csr_write(dut, REG_PERIOD_HS_L, 2, True)
    yield csr_write(dut, REG_FILTER, 0x00, True)
    
    yield csr_write(dut, REG_TX, 0x01, True)
    yield csr_write(dut, REG_TX, 0x00, True)
    yield csr_write(dut, REG_TX, 0x01, True)
    yield csr_write(dut, REG_TX, 0xcd, True)
    
    # TODO: reset rx...
    yield csr_write(dut, REG_TX_CTRL, BinaryValue("00000010"))
    
    yield Timer(50000000)
    
    dut._log.info("test_cdbus done.")

