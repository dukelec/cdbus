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
REG_SETTING         = 0x02
REG_IDLE_WAIT_LEN   = 0x04
REG_TX_PERMIT_LEN_L = 0x05
REG_TX_PERMIT_LEN_H = 0x06
REG_MAX_IDLE_LEN_L  = 0x07
REG_MAX_IDLE_LEN_H  = 0x08
REG_TX_PRE_LEN      = 0x09
REG_FILTER          = 0x0b
REG_DIV_LS_L        = 0x0c
REG_DIV_LS_H        = 0x0d
REG_DIV_HS_L        = 0x0e
REG_DIV_HS_H        = 0x0f
REG_INT_FLAG        = 0x10
REG_INT_MASK        = 0x11
REG_RX              = 0x14
REG_TX              = 0x15
REG_RX_CTRL         = 0x16
REG_TX_CTRL         = 0x17
REG_RX_ADDR         = 0x18
REG_RX_PAGE_FLAG    = 0x19
REG_FILTER1         = 0x1a
REG_FILTER2         = 0x1b

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

SPI_FREQ = 20000000
SPI_PERIOD = 1000000000000 / SPI_FREQ


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


async def spi_rw(dut, w_data = 0):
    r_data = 0
    for i in range(0,8):
        dut.sdi = 1 if (w_data & 0x80) else 0
        w_data = w_data << 1
        dut.sck_scl = 0
        await Timer(SPI_PERIOD / 2)
        dut.sck_scl = 1
        await ReadOnly()
        if dut.sdo_sda.value.binstr != 'z':
            r_data = (r_data << 1) | dut.sdo_sda.value.integer
        else:
            r_data = (r_data << 1) | 0
        await Timer(SPI_PERIOD / 2)
        dut.sck_scl = 0
    return r_data

async def spi_read(dut, address, len = 1):
    datas = []
    dut.nss = 0
    await Timer(SPI_PERIOD / 2)
    await spi_rw(dut, address)
    await Timer(SPI_PERIOD / 2)
    while len != 0:
        ret_val = await spi_rw(dut)
        datas.append(ret_val)
        await Timer(SPI_PERIOD / 2)
        len -= 1
    dut.nss = 1
    await Timer(SPI_PERIOD / 2)
    return datas

async def spi_write(dut, address, datas):
    dut.nss = 0
    await Timer(SPI_PERIOD / 2)
    await spi_rw(dut, address | 0x80)
    await Timer(SPI_PERIOD / 2)
    for data in datas:
        await spi_rw(dut, data)
        await Timer(SPI_PERIOD / 2)
    dut.nss = 1
    await Timer(SPI_PERIOD / 2)


@cocotb.test()
async def test_cdctl_bx(dut):
    """
    test_cdctl_bx
    """
    dut._log.info("test_cdctl_bx start.")
    dut.intf_sel = 1
    dut.nss = 1
    dut.sck_scl = 0

    cocotb.fork(Clock(dut.clk, CLK_PERIOD).start())
    await Timer(500000) # wait reset

    value = await spi_read(dut, REG_VERSION)
    dut._log.info("REG_VERSION: 0x%02x" % int(value[0]))
    value = await spi_read(dut, REG_SETTING)
    dut._log.info("REG_SETTING: 0x%02x" % int(value[0]))

    await spi_write(dut, REG_SETTING, [BinaryValue("00010001").integer])

    await spi_write(dut, REG_DIV_LS_H, [0])
    await spi_write(dut, REG_DIV_LS_L, [39])
    await spi_write(dut, REG_DIV_HS_H, [0])
    await spi_write(dut, REG_DIV_HS_L, [3])
    await spi_write(dut, REG_FILTER, [0x00])
    # TODO: reset rx...

    await spi_write(dut, REG_TX, [0x01])
    await spi_write(dut, REG_TX, [0x00])
    await spi_write(dut, REG_TX, [0x01, 0xcd])
    #await spi_write(dut, REG_TX, [0xcd])

    await spi_write(dut, REG_TX_CTRL, [BIT_TX_START | BIT_TX_RST_POINTER])

    
    await RisingEdge(dut.cdctl_bx_m.cdbus_m.rx_pending)
    value = await spi_read(dut, REG_RX, 3)
    print(" ".join([("%02x" % x) for x in value]))
    value = await spi_read(dut, REG_RX, 3)
    print(" ".join([("%02x" % x) for x in value]))
    
    
    #await RisingEdge(dut.cdctl_bx_m.cdbus_m.bus_idle)
    #await RisingEdge(dut.cdctl_bx_m.cdbus_m.bus_idle)
    await Timer(15000000)

    await send_frame(dut, b'\x05\x00\x01\xcd', 39, 3)
    
    await Timer(50000000)

    dut._log.info("test_cdctl_bx done.")

