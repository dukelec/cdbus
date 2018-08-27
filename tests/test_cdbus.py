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
from cocotb.result import ReturnValue, TestFailure

# pip3 install pycrc --user
from PyCRC.CRC16 import CRC16

def modbus_crc(data):
    return CRC16(modbus_flag = True).calculate(data).to_bytes(2, byteorder='little')


REG_VERSION         = 0x00
REG_SETTING         = 0x01
REG_IDLE_WAIT_LEN   = 0x02
REG_TX_WAIT_LEN     = 0x03
REG_FILTER          = 0x04
REG_DIV_LS_L        = 0x05
REG_DIV_LS_H        = 0x06
REG_DIV_HS_L        = 0x07
REG_DIV_HS_H        = 0x08
REG_INT_FLAG        = 0x09
REG_INT_MASK        = 0x0a
REG_RX              = 0x0b
REG_TX              = 0x0c
REG_RX_CTRL         = 0x0d
REG_TX_CTRL         = 0x0e
REG_RX_ADDR         = 0x0f
REG_RX_PAGE_FLAG    = 0x10
REG_FILTER1         = 0x11
REG_FILTER2         = 0x12

BIT_SETTING_TX_PUSH_PULL    = 1 << 0
BIT_SETTING_TX_INVERT       = 1 << 1
BIT_SETTING_USER_CRC        = 1 << 2
BIT_SETTING_NO_DROP         = 1 << 3
POS_SETTING_TX_EN_DELAY     =      4
BIT_SETTING_DIS_ARBITRATE   = 1 << 6

BIT_FLAG_BUS_IDLE           = 1 << 0
BIT_FLAG_RX_PENDING         = 1 << 1
BIT_FLAG_RX_LOST            = 1 << 2
BIT_FLAG_RX_ERROR           = 1 << 3
BIT_FLAG_TX_BUF_CLEAN       = 1 << 4
BIT_FLAG_TX_CD              = 1 << 5
BIT_FLAG_TX_ERROR           = 1 << 6

BIT_RX_RST_POINTER          = 1 << 0
BIT_RX_CLR_PENDING          = 1 << 1
BIT_RX_CLR_LOST             = 1 << 2
BIT_RX_CLR_ERROR            = 1 << 3
BIT_RX_RST                  = 1 << 4

BIT_TX_RST_POINTER          = 1 << 0
BIT_TX_START                = 1 << 1
BIT_TX_CLR_CD               = 1 << 2
BIT_TX_CLR_ERROR            = 1 << 3
BIT_TX_ABORT                = 1 << 4


CLK_FREQ = 40000000
CLK_PERIOD = 1000000000000 / CLK_FREQ


@cocotb.coroutine
def send_bytes(dut, bytes, factor, is_z = True):
    yield Timer(1000)
    factor += 1
    for byte in bytes:
        dut.bus_a = 0
        yield Timer(factor * CLK_PERIOD)
        for i in range(0,8):
            if byte & 0x01 == 0:
                dut.bus_a = 0
            else:
                dut.bus_a = BinaryValue("z") if is_z else 1
            yield Timer(factor * CLK_PERIOD)
            byte = byte >> 1
        dut.bus_a = BinaryValue("z") if is_z else 1
        yield Timer(factor * CLK_PERIOD)
        dut.bus_a = BinaryValue("z")

@cocotb.coroutine
def send_frame(dut, bytes, factor_l, factor_h):
    yield send_bytes(dut, bytes[0:1], factor_l)
    yield send_bytes(dut, bytes[1:], factor_h, False)
    yield send_bytes(dut, modbus_crc(bytes), factor_h, False)


@cocotb.coroutine
def reset(dut, duration = 10000):
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

    cocotb.fork(Clock(dut.clk, CLK_PERIOD).start())
    yield reset(dut)

    value = yield csr_read(dut, REG_VERSION, True)
    dut._log.info("REG_VERSION: 0x%02x" % int(value))
    value = yield csr_read(dut, REG_SETTING)
    dut._log.info("REG_SETTING: 0x%02x" % int(value))

    yield csr_write(dut, REG_SETTING, BinaryValue("00000001"))

    yield csr_write(dut, REG_DIV_LS_H, 0, True)
    yield csr_write(dut, REG_DIV_LS_L, 39, True) # 1Mbps
    yield csr_write(dut, REG_DIV_HS_H, 0, True)
    yield csr_write(dut, REG_DIV_HS_L, 3, True)  # 10Mbps
    yield csr_write(dut, REG_FILTER, 0x00, True) # set local filter to 0x00
    # TODO: reset rx...

    yield csr_write(dut, REG_TX, 0x01, True) # disguise as node 0x01 to send data
    yield csr_write(dut, REG_TX, 0x00, True)
    yield csr_write(dut, REG_TX, 0x01, True)
    yield csr_write(dut, REG_TX, 0xcd, True)
    yield csr_write(dut, REG_TX_CTRL, BIT_TX_START)

    yield Timer(40000000)
    yield csr_write(dut, REG_TX_CTRL, BIT_TX_ABORT)

    yield csr_write(dut, REG_TX, 0x0f, True) # disguise as node 0x0f to send data
    yield csr_write(dut, REG_TX, 0x00, True)
    yield csr_write(dut, REG_TX, 0x01, True)
    yield csr_write(dut, REG_TX, 0xcd, True)
    yield csr_write(dut, REG_TX_CTRL, BIT_TX_START)

    #yield RisingEdge(dut.cdbus_m.rx_pending)
    #yield RisingEdge(dut.cdbus_m.bus_idle)
    yield RisingEdge(dut.cdbus_m.bus_idle)
    yield Timer(5000000)

    yield send_frame(dut, b'\x05\x00\x01\xcd', 39, 3) # receive before previous packet send out
    yield Timer(100000000)

    dut._log.info("test_cdbus done.")

