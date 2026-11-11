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

I2C_FREQ = 2000000
I2C_PERIOD = round(1000000000000 / I2C_FREQ)
I2C_PERIOD_HALF = round(I2C_PERIOD / 2)
I2C_PERIOD_QUARTER = round(I2C_PERIOD / 4)

I2C_ADDR = 0x60 # {4'b1100, 1'b0, addr_sel[1:0]}, addr_sel: 00


async def i2c_start(dut):
    dut.sda_m.value = 1
    await Timer(I2C_PERIOD_HALF)
    dut.scl.value = 1
    await Timer(I2C_PERIOD_HALF)
    dut.sda_m.value = 0
    await Timer(I2C_PERIOD_HALF)
    dut.scl.value = 0
    await Timer(I2C_PERIOD_QUARTER)

async def i2c_stop(dut):
    dut.sda_m.value = 0
    await Timer(I2C_PERIOD_HALF)
    dut.scl.value = 1
    await Timer(I2C_PERIOD_HALF)
    dut.sda_m.value = 1
    await Timer(I2C_PERIOD_HALF)

async def i2c_wbyte(dut, data):
    for i in range(0, 8):
        dut.sda_m.value = 1 if (data & 0x80) else 0
        data = (data << 1) & 0xff
        await Timer(I2C_PERIOD_HALF)
        dut.scl.value = 1
        await Timer(I2C_PERIOD_HALF)
        dut.scl.value = 0
        await Timer(I2C_PERIOD_QUARTER)
    # ack
    dut.sda_m.value = 1
    await Timer(I2C_PERIOD_HALF)
    dut.scl.value = 1
    ack = str(dut.sda.value) == '0'
    await Timer(I2C_PERIOD_HALF)
    dut.scl.value = 0
    await Timer(I2C_PERIOD_QUARTER)
    return ack

async def i2c_rbyte(dut, ack=True):
    val = 0
    dut.sda_m.value = 1
    for i in range(0, 8):
        await Timer(I2C_PERIOD_HALF)
        dut.scl.value = 1
        val = (val << 1) | (0 if str(dut.sda.value) == '0' else 1)
        await Timer(I2C_PERIOD_HALF)
        dut.scl.value = 0
        await Timer(I2C_PERIOD_QUARTER)
    # master ack / nack
    dut.sda_m.value = 0 if ack else 1
    await Timer(I2C_PERIOD_HALF)
    dut.scl.value = 1
    await Timer(I2C_PERIOD_HALF)
    dut.scl.value = 0
    await Timer(I2C_PERIOD_QUARTER)
    dut.sda_m.value = 1
    await Timer(I2C_PERIOD_QUARTER)
    return val


class I2cIo:
    crc_head = [I2C_ADDR << 1]

    def __init__(self, dut):
        self.dut = dut
        self.rx_pending = dut.cdctl_i2c_m.cdbus_m.rx_pending
        self.sdo_early = None

    def crc_mid(self, status):
        return [(I2C_ADDR << 1) | 1, status]

    def cmd(self, address, is_write):
        return address

    async def write(self, datas):
        await i2c_start(self.dut)
        ack = await i2c_wbyte(self.dut, I2C_ADDR << 1)
        for data in datas:
            ack = await i2c_wbyte(self.dut, data)
        await i2c_stop(self.dut)
        await Timer(I2C_PERIOD + CLK_PERIOD)
        return ack

    # the bytes of w_datas, repeated start, then r_len bytes from the device
    async def xfer_read(self, w_datas, r_len):
        ret = []
        await i2c_start(self.dut)
        await i2c_wbyte(self.dut, I2C_ADDR << 1)
        for data in w_datas:
            await i2c_wbyte(self.dut, data)
        await i2c_start(self.dut)
        await i2c_wbyte(self.dut, (I2C_ADDR << 1) | 1)
        for i in range(r_len):
            ret.append(await i2c_rbyte(self.dut, i != r_len - 1))
        await i2c_stop(self.dut)
        await Timer(I2C_PERIOD + CLK_PERIOD)
        return ret

    async def read(self, address, len):
        return await self.xfer_read([address], len)

    # address, n-1, repeated start, write status, data, crc16
    async def crc_read(self, address, len):
        ret = await self.xfer_read([address, len - 1], 1 + len + 2)
        return ret[0], ret[1:-2], ret[-2] << 8 | ret[-1]


@cocotb.test(timeout_time=20000, timeout_unit='us')
async def test_cdctl_i2c_crc(dut):
    """
    test_cdctl_i2c_crc
    """
    dut._log.info("test_cdctl_i2c_crc start.")
    dut.sda_m.value = 1
    dut.scl.value = 1

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD).start())
    await Timer(500000) # wait reset

    await CrcMode(dut, I2cIo(dut)).run(CLK_FREQ)

    dut._log.info("test_cdctl_i2c_crc done.")
    await exit_ok()
