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


# returns None if sdo is not driven
async def spi_rw(dut, w_data = 0):
    r_data = 0
    is_z = True
    for i in range(0,8):
        dut.sdi.value = 1 if (w_data & 0x80) else 0
        w_data = w_data << 1
        dut.sck.value = 0
        await Timer(SPI_PERIOD_HALF)
        dut.sck.value = 1
        if dut.sdo.value != Logic('z'):
            r_data = (r_data << 1) | int(dut.sdo.value)
            is_z = False
        else:
            r_data = (r_data << 1) | 0
        await Timer(SPI_PERIOD_HALF)
        dut.sck.value = 0
    return None if is_z else r_data

# one transfer, returns the bytes on sdo
async def spi_xfer(dut, datas):
    ret = []
    dut.nss.value = 0
    await Timer(SPI_PERIOD_HALF)
    for data in datas:
        ret.append(await spi_rw(dut, data))
        await Timer(SPI_PERIOD_HALF)
    dut.nss.value = 1
    await Timer(SPI_PERIOD_HALF + CLK_PERIOD)
    return ret


class SpiIo:
    crc_head = []

    def __init__(self, dut):
        self.dut = dut
        self.rx_pending = dut.cdctl_spi_m.cdbus_m.rx_pending
        self.sdo_early = dut.cdctl_spi_m.spi_slave_m.sdo_early

    def crc_mid(self, status):
        return [status]

    def cmd(self, address, is_write):
        return (address << 1) | (0x80 if is_write else 0)

    async def write(self, datas):
        await spi_xfer(self.dut, datas)

    async def read(self, address, len):
        return (await spi_xfer(self.dut, [address << 1] + [0] * len))[1:]

    # cmd and n-1 from the host, then write status, data and crc16 from the device
    async def crc_read(self, address, len):
        ret = await spi_xfer(self.dut, [address << 1, len - 1] + [0] * (len + 3))
        assert ret[0:2] == [None, None], 'sdo driven during cmd or n-1' # 3-wire: sdo tied to sdi
        return ret[2], ret[3:-2], ret[-2] << 8 | ret[-1]


@cocotb.test(timeout_time=5000, timeout_unit='us')
async def test_cdctl_spi_crc(dut):
    """
    test_cdctl_spi_crc
    """
    dut._log.info("test_cdctl_spi_crc start.")
    dut.nss.value = 1
    dut.sck.value = 0

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD).start())
    await Timer(500000) # wait reset

    await CrcMode(dut, SpiIo(dut)).run(CLK_FREQ)

    dut._log.info("test_cdctl_spi_crc done.")
    await exit_ok()
