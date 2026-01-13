# This Source Code Form is subject to the terms of the Mozilla
# Public License, v. 2.0. If a copy of the MPL was not distributed
# with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Notice: The scope granted to MPL excludes the ASIC industry.
#
# Copyright (c) 2017 DUKELEC, All rights reserved.
#
# Author: Duke Fong <d@d-l.io>
#

from common import *

CLK_FREQ = 40000000
CLK_PERIOD = round(1000000000000 / CLK_FREQ)

SPI_FREQ = 32000000
SPI_PERIOD = round(1000000000000 / SPI_FREQ)
SPI_PERIOD_HALF = round(SPI_PERIOD / 2)


async def spi_rw(dut, w_data = 0):
    r_data = 0
    for i in range(0,8):
        dut.sdi.value = 1 if (w_data & 0x80) else 0
        w_data = w_data << 1
        dut.sck.value = 0
        await Timer(SPI_PERIOD_HALF)
        dut.sck.value = 1
        #await ReadOnly()
        if dut.sdo.value != Logic('z'):
            r_data = (r_data << 1) | int(dut.sdo.value)
        else:
            r_data = (r_data << 1) | 0
        await Timer(SPI_PERIOD_HALF)
        dut.sck.value = 0
    return r_data

async def spi_read(dut, address, len = 1):
    datas = []
    dut.nss.value = 0
    await Timer(SPI_PERIOD_HALF)
    await spi_rw(dut, address << 1)
    await Timer(SPI_PERIOD_HALF)
    while len != 0:
        ret_val = await spi_rw(dut)
        datas.append(ret_val)
        await Timer(SPI_PERIOD_HALF)
        len -= 1
    #await Timer(CLK_PERIOD * 2)
    dut.nss.value = 1
    await Timer(SPI_PERIOD_HALF + CLK_PERIOD)
    return datas

async def spi_write(dut, address, datas):
    dut.nss.value = 0
    await Timer(SPI_PERIOD_HALF)
    await spi_rw(dut, (address << 1) | 0x80)
    await Timer(SPI_PERIOD_HALF)
    for data in datas:
        await spi_rw(dut, data)
        await Timer(SPI_PERIOD_HALF)
    #await Timer(CLK_PERIOD * 2)
    dut.nss.value = 1
    await Timer(SPI_PERIOD_HALF + CLK_PERIOD)


@cocotb.test(timeout_time=2500, timeout_unit='us')
async def test_cdctl_spi(dut):
    """
    test_cdctl_spi
    """
    dut._log.info("test_cdctl_spi start.")
    dut.nss.value = 1
    dut.sck.value = 0

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD).start())
    await Timer(500000) # wait reset

    value = await spi_read(dut, REG_VERSION)
    dut._log.info("REG_VERSION: 0x%02x" % int(value[0]))
    value = await spi_read(dut, REG_SETTING)
    dut._log.info("REG_SETTING: 0x%02x" % int(value[0]))

    await spi_write(dut, REG_SETTING, [0b00010001])

    await spi_write(dut, REG_DIV_LS_H, [0])
    await spi_write(dut, REG_DIV_LS_L, [39])
    await spi_write(dut, REG_DIV_HS_H, [0])
    await spi_write(dut, REG_DIV_HS_L, [3])
    await spi_write(dut, REG_FILTER, [0x00])

    await spi_write(dut, REG_DAT, [0x01, 0x00, 0x01, 0xcd])

    await RisingEdge(dut.cdctl_spi_m.cdbus_m.rx_pending)
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
    
    
    #await RisingEdge(dut.cdctl_spi_m.cdbus_m.bus_idle)
    #await RisingEdge(dut.cdctl_spi_m.cdbus_m.bus_idle)
    await Timer(15000000)

    await send_frame(dut, b'\x05\x00\x01\xcd', CLK_FREQ, 39, 3)
    await Timer(15000000)
    
    int_flag = (await spi_read(dut, REG_INT_FLAG_L, 2))
    dut._log.info(f"int_flag: {int_flag[0]:02x} {int_flag[1]:02x}")
    await Timer(50000000)

    dut._log.info("test_cdctl_spi done.")
    await exit_ok()

