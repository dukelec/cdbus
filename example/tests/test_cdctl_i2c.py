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

from common import *

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

async def i2c_read(dut, address, len = 1):
    datas = []
    await i2c_start(dut)
    await i2c_wbyte(dut, I2C_ADDR << 1)
    await i2c_wbyte(dut, address)
    await i2c_start(dut) # repeated start
    await i2c_wbyte(dut, (I2C_ADDR << 1) | 1)
    while len != 0:
        datas.append(await i2c_rbyte(dut, len != 1))
        len -= 1
    await i2c_stop(dut)
    await Timer(I2C_PERIOD + CLK_PERIOD)
    return datas

async def i2c_write(dut, address, datas):
    await i2c_start(dut)
    await i2c_wbyte(dut, I2C_ADDR << 1)
    await i2c_wbyte(dut, address)
    for data in datas:
        await i2c_wbyte(dut, data)
    await i2c_stop(dut)
    await Timer(I2C_PERIOD + CLK_PERIOD)


@cocotb.test(timeout_time=2500, timeout_unit='us')
async def test_cdctl_i2c(dut):
    """
    test_cdctl_i2c
    """
    dut._log.info("test_cdctl_i2c start.")
    dut.sda_m.value = 1
    dut.scl.value = 1

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD).start())
    await Timer(500000) # wait reset

    value = await i2c_read(dut, REG_VERSION)
    dut._log.info("REG_VERSION: 0x%02x" % int(value[0]))
    if value[0] != DFT_VERSION:
        dut._log.error('version mismatch')
        await exit_err()
    value = await i2c_read(dut, REG_SETTING)
    dut._log.info("REG_SETTING: 0x%02x" % int(value[0]))

    await i2c_write(dut, REG_SETTING, [0b00010001])

    await i2c_write(dut, REG_DIV_LS_H, [0])
    await i2c_write(dut, REG_DIV_LS_L, [39])
    await i2c_write(dut, REG_DIV_HS_H, [0])
    await i2c_write(dut, REG_DIV_HS_L, [3])
    await i2c_write(dut, REG_FILTER, [0x00])

    # tx page submitted automatically at stop
    await i2c_write(dut, REG_DAT, [0x01, 0x00, 0x01, 0xcd])

    await RisingEdge(dut.cdctl_i2c_m.cdbus_m.rx_pending)
    int_flag, rx_len = await i2c_read(dut, REG_INT_FLAG_L, 2)
    dut._log.info(f"int_flag: {int_flag:02x}")
    dut._log.info(f"rx_len: {rx_len:02x}")

    # rx page released automatically at stop
    value = await i2c_read(dut, REG_DAT, 3 + rx_len)
    dut._log.info(" ".join([("%02x" % x) for x in value]))
    if bytes(value) != b'\x01\x00\x01\xcd':
        dut._log.error('rx data mismatch')
        await exit_err()

    int_flag = (await i2c_read(dut, REG_INT_FLAG_L))[0]
    dut._log.info(f"int_flag: {int_flag:02x}")

    int_flag = (await i2c_read(dut, REG_INT_FLAG_L))[0]
    dut._log.info(f"int_flag: {int_flag:02x}")
    if int_flag != 0x30:
        dut._log.error(f'wrong int_flag')
        await exit_err()

    await Timer(15000000)

    await send_frame(dut, b'\x05\x00\x01\xcd', CLK_FREQ, 39, 3)
    await Timer(15000000)

    int_flag, rx_len = await i2c_read(dut, REG_INT_FLAG_L, 2)
    dut._log.info(f"int_flag: {int_flag:02x} rx_len: {rx_len:02x}")

    value = await i2c_read(dut, REG_DAT, 3 + rx_len)
    dut._log.info(" ".join([("%02x" % x) for x in value]))
    if bytes(value) != b'\x05\x00\x01\xcd':
        dut._log.error('rx data mismatch')
        await exit_err()

    dut._log.info("test_cdctl_i2c done.")
    await exit_ok()
