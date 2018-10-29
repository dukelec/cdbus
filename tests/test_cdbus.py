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
REG_WAIT_LEN        = 0x02
REG_FILTER          = 0x03
REG_DIV             = 0x04
REG_INT_FLAG        = 0x05
REG_INT_MASK        = 0x06
REG_RX_CTRL         = 0x07
REG_TX_CTRL         = 0x08
REG_RX_PAGE_FLAG    = 0x09
REG_FILTER_M        = 0x0a

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

BIT_RX_CLR_PENDING          = 1 << 1
BIT_RX_CLR_LOST             = 1 << 2
BIT_RX_CLR_ERROR            = 1 << 3
BIT_RX_RST                  = 1 << 4

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
    dut.csr_byteenable = BinaryValue("1111")
    dut.csr_writedata = data
    dut.csr_write = 1

    if not burst:
        yield RisingEdge(dut.clk)
        dut.csr_write = 0
        dut.csr_address = BinaryValue("x" * len(dut.csr_address))
        dut.csr_writedata = BinaryValue("x" * len(dut.csr_writedata))

@cocotb.coroutine
def rx_mm_read(dut, address):
    yield RisingEdge(dut.clk)
    dut.rx_mm_address = address
    dut.rx_mm_byteenable = BinaryValue("1111")
    dut.rx_mm_read = 1

    yield RisingEdge(dut.clk)
    dut.rx_mm_read = 0
    dut.rx_mm_address = BinaryValue("x" * len(dut.rx_mm_address))
    yield ReadOnly()
    data = dut.rx_mm_readdata.value

    raise ReturnValue(data)

@cocotb.coroutine
def tx_mm_write(dut, address, data, burst = False):
    yield RisingEdge(dut.clk)
    dut.tx_mm_address = address
    dut.tx_mm_byteenable = BinaryValue("1111")
    dut.tx_mm_writedata = data
    dut.tx_mm_write = 1

    if not burst:
        yield RisingEdge(dut.clk)
        dut.tx_mm_write = 0
        dut.tx_mm_address = BinaryValue("x" * len(dut.tx_mm_address))
        dut.tx_mm_writedata = BinaryValue("x" * len(dut.tx_mm_writedata))


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

    yield csr_write(dut, REG_DIV, (3 << 16) | 39, True)
    yield csr_write(dut, REG_FILTER, 0x00, True) # set local filter to 0x00
    yield csr_write(dut, REG_WAIT_LEN, (0x01 << 16) | 0x04, True)
    yield csr_write(dut, REG_FILTER_M, (0xff << 8) | 0x09, True)
    # TODO: reset rx...

    # disguise as node 0x01 to send data: 01 00 01 cd
    yield tx_mm_write(dut, 0x00, 0xcd010001, False)
    yield csr_write(dut, REG_TX_CTRL, BIT_TX_START)

    yield Timer(40000000)
    yield csr_write(dut, REG_TX_CTRL, BIT_TX_ABORT)
    yield Timer(10000000)

    # disguise as node 0x01 to send data: 0f 08 01 cd
    yield tx_mm_write(dut, 0x00, 0xcd02080f, True)
    yield tx_mm_write(dut, 0x01, 0x000000dd, False)
    yield csr_write(dut, REG_TX_CTRL, BIT_TX_START)

    #yield RisingEdge(dut.cdbus_m.rx_pending)
    #yield RisingEdge(dut.cdbus_m.bus_idle)
    ###yield RisingEdge(dut.cdbus_m.bus_idle)
    ###yield Timer(5000000)

    yield send_frame(dut, b'\x01\x00\x01\xcd', 39, 3) # receive before previous packet send out
    yield Timer(100000000)

    value = yield rx_mm_read(dut, 0x00)
    dut._log.info("read: 0x%08x" % int(value))
    yield Timer(100000000)

    dut._log.info("test_cdbus done.")

