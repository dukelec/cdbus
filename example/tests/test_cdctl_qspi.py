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
from common import *

CLK_FREQ = 40000000
CLK_PERIOD = round(1000000000000 / CLK_FREQ)

SPI_FREQ = 32000000
SPI_PERIOD = round(1000000000000 / SPI_FREQ)
SPI_PERIOD_HALF = round(SPI_PERIOD / 2)


async def spi_rw(dut, w_data = 0):
    r_data = 0
    for i in range(0,2):
        if w_data != None:
            dut.sdio.value = w_data >> 4
            w_data = (w_data << 4) & 0xff
        dut.sck.value = 0
        await Timer(SPI_PERIOD_HALF)
        dut.sck.value = 1
        #await ReadOnly()
        if dut.sdio.value.binstr != 'zzzz':
            r_data = (r_data << 4) | dut.sdio.value.integer
        else:
            r_data = (r_data << 4) | 0
        await Timer(SPI_PERIOD_HALF)
        dut.sck.value = 0
    return r_data

async def spi_read(dut, address, len = 1):
    datas = []
    dut.nss.value = 0
    await Timer(SPI_PERIOD_HALF)
    await spi_rw(dut, address)
    #await Timer(SPI_PERIOD_HALF)
    dut.sdio.value = BinaryValue("zzzz")
    #await Timer(SPI_PERIOD_HALF)
    await spi_rw(dut, None)
    await spi_rw(dut, None)
    #await Timer(SPI_PERIOD_HALF)
    while len != 0:
        ret_val = await spi_rw(dut, None)
        datas.append(ret_val)
        len -= 1
        #await Timer(SPI_PERIOD_HALF)
    await Timer(SPI_PERIOD_HALF)
    #await Timer(SPI_PERIOD * 2)
    dut.nss.value = 1
    await Timer((SPI_PERIOD_HALF + CLK_PERIOD) * 2)
    return datas

async def spi_write(dut, address, datas):
    dut.nss.value = 0
    await Timer(SPI_PERIOD_HALF)
    await spi_rw(dut, address | 0x80)
    #await Timer(SPI_PERIOD_HALF)
    for data in datas:
        await spi_rw(dut, data)
        #await Timer(SPI_PERIOD_HALF)
    await Timer(SPI_PERIOD_HALF)
    #await Timer(SPI_PERIOD * 2)
    dut.nss.value = 1
    await Timer((SPI_PERIOD_HALF + CLK_PERIOD) * 2)


@cocotb.test(timeout_time=2500, timeout_unit='us')
async def test_cdctl_qspi(dut):
    """
    test_cdctl_qspi
    """
    dut._log.info("test_cdctl_qspi start.")
    dut.nss.value = 1
    dut.sck.value = 0

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD).start())
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

    await spi_write(dut, REG_DAT, [0x01, 0x00, 0x01, 0xcd])

    await RisingEdge(dut.cdctl_qspi_m.cdbus_m.rx_pending)
    int_flag, rx_len = await spi_read(dut, REG_INT_FLAG_L, 2)
    dut._log.info(f"int_flag: {int_flag:02x}")
    dut._log.info(f"rx_len: {rx_len:02x}")
    
    value = await spi_read(dut, REG_DAT, 3 + rx_len)
    dut._log.info(" ".join([("%02x" % x) for x in value]))
    
    int_flag = (await spi_read(dut, REG_INT_FLAG_L))[0]
    dut._log.info(f"int_flag: {int_flag:02x}")
    
    int_flag = (await spi_read(dut, REG_INT_FLAG_L))[0]
    dut._log.info(f"int_flag: {int_flag:02x}")
    if int_flag != 0x30:
        dut._log.error(f'wrong int_flag')
    
    
    #await RisingEdge(dut.cdctl_qspi_m.cdbus_m.bus_idle)
    #await RisingEdge(dut.cdctl_qspi_m.cdbus_m.bus_idle)
    await Timer(15000000)

    await send_frame(dut, b'\x05\x00\x01\xcd', CLK_FREQ, 39, 3)
    await Timer(15000000)
    
    int_flag = (await spi_read(dut, REG_INT_FLAG_L, 2))
    dut._log.info(f"int_flag: {int_flag[0]:02x} {int_flag[1]:02x}")
    await Timer(50000000)

    dut._log.info("test_cdctl_qspi done.")
    await exit_ok()

