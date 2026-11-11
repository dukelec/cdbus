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

from crc_mode import *

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
        if dut.sdio.value != LogicArray('zzzz'):
            r_data = (r_data << 4) | int(dut.sdio.value)
        else:
            r_data = (r_data << 4) | 0
        await Timer(SPI_PERIOD_HALF)
        dut.sck.value = 0
    return r_data

# one transfer: the bytes of w_datas from the host, then r_len bytes from the device
async def spi_xfer(dut, w_datas, r_len = 0):
    ret = []
    dut.nss.value = 0
    await Timer(SPI_PERIOD_HALF)
    for data in w_datas:
        await spi_rw(dut, data)
    dut.sdio.value = LogicArray('zzzz')
    for i in range(r_len):
        ret.append(await spi_rw(dut, None))
    await Timer(SPI_PERIOD_HALF)
    dut.nss.value = 1
    await Timer(round(CLK_PERIOD * 2.2)) # little more than the 2 clocks chip_select needs
    return ret


class QspiIo:
    crc_head = []

    def __init__(self, dut):
        self.dut = dut
        self.rx_pending = dut.cdctl_qspi_m.cdbus_m.rx_pending
        self.sdo_early = dut.cdctl_qspi_m.qspi_slave_m.sdo_early

    def crc_mid(self, status):
        return [status]

    def cmd(self, address, is_write):
        return address | (0x80 if is_write else 0)

    async def write(self, datas):
        await spi_xfer(self.dut, datas)

    # cmd, 2 dummy bytes, data
    async def read(self, address, len):
        return (await spi_xfer(self.dut, [address], 2 + len))[2:]

    # cmd, n-1, dummy, write status, data, crc16
    async def crc_read(self, address, len):
        ret = await spi_xfer(self.dut, [address, len - 1], 2 + len + 2)
        return ret[1], ret[2:-2], ret[-2] << 8 | ret[-1]


@cocotb.test(timeout_time=5000, timeout_unit='us')
async def test_cdctl_qspi_crc(dut):
    """
    test_cdctl_qspi_crc
    """
    dut._log.info("test_cdctl_qspi_crc start.")
    dut.nss.value = 1
    dut.sck.value = 0

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD).start())
    await Timer(500000) # wait reset

    await CrcMode(dut, QspiIo(dut)).run(CLK_FREQ)

    dut._log.info("test_cdctl_qspi_crc done.")
    await exit_ok()
