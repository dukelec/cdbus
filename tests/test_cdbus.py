# This Source Code Form is subject to the terms of the Mozilla
# Public License, v. 2.0. If a copy of the MPL was not distributed
# with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Notice: The scope granted to MPL excludes the ASIC industry.
#
# Copyright (c) 2017 DUKELEC, All rights reserved.
#
# Author: Duke Fong <d@d-l.io>
#

import cocotb
from cocotb.binary import BinaryValue
from cocotb.triggers import RisingEdge, ReadOnly, Timer
from cocotb.clock import Clock

# pip3 install pythoncrc
from PyCRC.CRC16 import CRC16

def modbus_crc(data):
    return CRC16(modbus_flag = True).calculate(data).to_bytes(2, byteorder='little')


REG_VERSION         = 0x00
REG_SETTING         = 0x01
REG_IDLE_WAIT_LEN   = 0x02
REG_TX_PERMIT_LEN   = 0x03
REG_MAX_IDLE_LEN    = 0x04
REG_TX_PRE_LEN      = 0x05
REG_FILTER          = 0x06
REG_DIV_LS          = 0x07
REG_DIV_HS          = 0x08
REG_INT_FLAG        = 0x09
REG_INT_MASK        = 0x0a
REG_RX_CTRL         = 0x0b
REG_TX_CTRL         = 0x0c
REG_RX_PAGE_FLAG    = 0x0d
REG_FILTER_M        = 0x0e

BIT_SETTING_TX_PUSH_PULL    = 1 << 0
BIT_SETTING_TX_INVERT       = 1 << 1
BIT_SETTING_USER_CRC        = 1 << 2
BIT_SETTING_NO_DROP         = 1 << 3
BIT_SETTING_ARBITRATE       = 1 << 4
BIT_SETTING_BREAK_SYNC      = 1 << 5
BIT_SETTING_FULL_DUPLEX     = 1 << 6

BIT_FLAG_BUS_IDLE           = 1 << 0
BIT_FLAG_RX_PENDING         = 1 << 1
BIT_FLAG_RX_BREAK           = 1 << 2
BIT_FLAG_RX_LOST            = 1 << 3
BIT_FLAG_RX_ERROR           = 1 << 4
BIT_FLAG_TX_BUF_CLEAN       = 1 << 5
BIT_FLAG_TX_CD              = 1 << 6
BIT_FLAG_TX_ERROR           = 1 << 7

BIT_RX_RST_POINTER          = 1 << 0
BIT_RX_CLR_PENDING          = 1 << 1
BIT_RX_CLR_LOST             = 1 << 2
BIT_RX_CLR_ERROR            = 1 << 3
BIT_RX_RST                  = 1 << 4
BIT_RX_CLR_BREAK            = 1 << 5

BIT_TX_RST_POINTER          = 1 << 0
BIT_TX_START                = 1 << 1
BIT_TX_CLR_CD               = 1 << 2
BIT_TX_CLR_ERROR            = 1 << 3
BIT_TX_ABORT                = 1 << 4
BIT_TX_SEND_BREAK           = 1 << 5


CLK_FREQ = 40000000
CLK_PERIOD = 1000000000000 / CLK_FREQ


async def send_bytes(dut, bytes, factor, is_z = True):
    await Timer(1000)
    factor += 1
    for byte in bytes:
        dut.bus_a = 0
        await Timer(factor * CLK_PERIOD)
        for i in range(0,8):
            if byte & 0x01 == 0:
                dut.bus_a = 0
            else:
                dut.bus_a = BinaryValue("z") if is_z else 1
            await Timer(factor * CLK_PERIOD)
            byte = byte >> 1
        dut.bus_a = BinaryValue("z") if is_z else 1
        await Timer(factor * CLK_PERIOD)
        dut.bus_a = BinaryValue("z")

async def send_frame(dut, bytes, factor_l, factor_h):
    await send_bytes(dut, bytes[0:1], factor_l)
    await send_bytes(dut, bytes[1:], factor_h, False)
    await send_bytes(dut, modbus_crc(bytes), factor_h, False)


async def reset(dut, duration = 10000):
    dut._log.debug("Resetting DUT")
    dut.reset_n = 0
    await Timer(duration)
    await RisingEdge(dut.clk)
    dut.reset_n = 1
    dut._log.debug("Out of reset")

async def csr_read(dut, address):
    await RisingEdge(dut.clk)
    dut.csr_address = address
    dut.csr_read = 1

    await RisingEdge(dut.clk)
    data = dut.csr_readdata.value
    dut.csr_read = 0
    dut.csr_address = BinaryValue("x" * len(dut.csr_address))
    await ReadOnly()

    return data

async def csr_write(dut, address, data, burst = False):
    await RisingEdge(dut.clk)
    dut.csr_address = address
    dut.csr_byteenable = BinaryValue("1111")
    dut.csr_writedata = data
    dut.csr_write = 1

    if not burst:
        await RisingEdge(dut.clk)
        dut.csr_write = 0
        dut.csr_address = BinaryValue("x" * len(dut.csr_address))
        dut.csr_writedata = BinaryValue("x" * len(dut.csr_writedata))

async def rx_mm_read(dut, address):
    await RisingEdge(dut.clk)
    dut.rx_mm_address = address
    dut.rx_mm_byteenable = BinaryValue("1111")
    dut.rx_mm_read = 1

    await RisingEdge(dut.clk)
    dut.rx_mm_read = 0
    dut.rx_mm_address = BinaryValue("x" * len(dut.rx_mm_address))
    await ReadOnly()
    data = dut.rx_mm_readdata.value

    return data

async def tx_mm_write(dut, address, data, burst = False):
    await RisingEdge(dut.clk)
    dut.tx_mm_address = address
    dut.tx_mm_byteenable = BinaryValue("1111")
    dut.tx_mm_writedata = data
    dut.tx_mm_write = 1

    if not burst:
        await RisingEdge(dut.clk)
        dut.tx_mm_write = 0
        dut.tx_mm_address = BinaryValue("x" * len(dut.tx_mm_address))
        dut.tx_mm_writedata = BinaryValue("x" * len(dut.tx_mm_writedata))


@cocotb.test()
async def test_cdbus(dut):
    """
    test_cdbus
    """
    dut._log.info("test_cdbus start.")

    cocotb.fork(Clock(dut.clk, CLK_PERIOD).start())
    await reset(dut)

    value = await csr_read(dut, REG_VERSION)
    dut._log.info("REG_VERSION: 0x%02x" % int(value))
    value = await csr_read(dut, REG_SETTING)
    dut._log.info("REG_SETTING: 0x%02x" % int(value))

    await csr_write(dut, REG_SETTING, BinaryValue("00010001"))

    await csr_write(dut, REG_DIV_LS, 39, True)
    await csr_write(dut, REG_DIV_HS, 3, True)
    await csr_write(dut, REG_FILTER, 0x00, True) # set local filter to 0x00
    # TODO: reset rx...

    # disguise as node 0x01 to send data: 01 00 01 cd
    await tx_mm_write(dut, 0x00, 0xcd010001, False)
    await csr_write(dut, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER)

    await Timer(40000000)
    await csr_write(dut, REG_TX_CTRL, BIT_TX_ABORT)

    # disguise as node 0x01 to send data: 0f 08 02 cd dd
    await tx_mm_write(dut, 0x00, 0xcd02080f, True)
    await tx_mm_write(dut, 0x01, 0x000000dd, False)
    await csr_write(dut, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER)

    #await RisingEdge(dut.cdbus_m.rx_pending)
    #await RisingEdge(dut.cdbus_m.bus_idle)
    await RisingEdge(dut.cdbus_m.bus_idle)
    await Timer(5000000)

    await send_frame(dut, b'\x05\x00\x01\xcd', 39, 3) # receive before previous packet send out
    await Timer(100000000)

    value = await rx_mm_read(dut, 0x00)
    dut._log.info("read: 0x%08x" % int(value))
    await Timer(100000000)

    dut._log.info("test_cdbus done.")

