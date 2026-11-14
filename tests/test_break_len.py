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
from cocotb.utils import get_sim_time

BIT_NS = 100 # 10Mbps

def now():
    return get_sim_time(unit='ns')

# returns: TX_EN pre-assert time and break low time, in bits
async def measure_break(dut, wait_en=True):
    t0 = 0
    if wait_en:
        await RisingEdge(dut.tx_en0)
        t0 = now()
    await FallingEdge(dut.tx0)
    t1 = now()
    await RisingEdge(dut.tx0)
    t2 = now()
    return (t1 - t0) / BIT_NS, (t2 - t1) / BIT_NS

@cocotb.test(timeout_time=500, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')

    sys_clk = 40000000
    clk_period = 1000000000000 / sys_clk

    cocotb.start_soon(Clock(dut.clk0, clk_period).start())
    cocotb.start_soon(Clock(dut.clk1, clk_period).start())
    cocotb.start_soon(Clock(dut.clk2, clk_period).start())
    for i in range(3):
        await reset(dut, i)
        await check_version(dut, i)
        await csr_write(dut, i, REG_SETTING, BIT_SETTING_MODE_HALF)
        await csr_write(dut, i, REG_PIN_CFG, BIT_PIN_CFG_TX_PUSH_PULL)
        await set_div(dut, i, 3, 3)
    await csr_write(dut, 0, REG_FILTER, 0x55)
    await csr_write(dut, 2, REG_FILTER, 0x03)
    await csr_write(dut, 2, REG_INT_MASK_L, 0b00001111)

    val = await csr_read(dut, 0, REG_TX_CFG)
    if int(val) != 0x01:
        dut._log.error(f'idx0: wrong default REG_TX_CFG: 0x{int(val):02x}')
        await exit_err()
    await csr_write(dut, 0, REG_TX_CFG, 0xff)
    val = await csr_read(dut, 0, REG_TX_CFG)
    if int(val) != 0xf7:
        dut._log.error(f'idx0: wrong REG_TX_CFG read back: 0x{int(val):02x}')
        await exit_err()

    # break sent by user
    for pre, ext in ((1, 0), (0, 1), (3, 3), (4, 8), (7, 15)):
        await csr_write(dut, 0, REG_TX_CFG, ext << 4 | pre)
        await csr_write(dut, 0, REG_CTRL, BIT_TX_SEND_BREAK)
        pre_len, brk_len = await measure_break(dut)
        dut._log.info(f'pre {pre}, ext {ext}: measured pre {pre_len}, break {brk_len} bits')
        if abs(pre_len - pre) > 0.5 or abs(brk_len - (10 + ext)) > 0.5:
            dut._log.error(f'idx0: wrong pre or break length')
            await exit_err()

        await Timer(3 * BIT_NS, unit='ns')
        val = await read_int_flag(dut, 2)
        if int(val) & 0x0f != BIT_FLAG_RX_BREAK:
            dut._log.error(f'idx2: wrong flag after break: 0x{int(val):02x}')
            await exit_err()
        await Timer(15 * BIT_NS, unit='ns')
        val = await read_int_flag(dut, 2)
        if int(val) & 0x0f:
            dut._log.error(f'idx2: wrong flag after bus idle: 0x{int(val):02x}')
            await exit_err()

    # normal frame is not affected
    await write_tx(dut, 0, b'\x55\x03\x01\xc5')
    await RisingEdge(dut.irq2)
    val = await read_int_flag(dut, 2)
    str_ = (await read_rx(dut, 2, 4)).hex()
    dut._log.info(f'idx2: flag: 0x{int(val):02x}, received: {str_}')
    if int(val) & 0x0f != BIT_FLAG_RX_PENDING or str_ != '550301c5':
        dut._log.error(f'idx2: receive mismatch')
        await exit_err()

    # break generated automatically in bs mode
    for i in range(3):
        await csr_write(dut, i, REG_SETTING, BIT_SETTING_MODE_BS)
        await set_max_idle_len(dut, i, 40)
        await set_tx_permit_len(dut, i, 10 + i * 10)
    await csr_write(dut, 2, REG_INT_MASK_L, 0b00001101) # not select break rx

    for ext in (0, 5):
        await csr_write(dut, 0, REG_TX_CFG, ext << 4 | 1)
        await Timer(80 * BIT_NS, unit='ns') # wait exceed max idle
        cocotb.start_soon(write_tx(dut, 0, b'\x55\x03\x01\xc5'))
        _, brk_len = await measure_break(dut, False)
        dut._log.info(f'bs mode, ext {ext}: measured break {brk_len} bits')
        if abs(brk_len - (10 + ext)) > 0.5:
            dut._log.error(f'idx0: wrong break length')
            await exit_err()

        await RisingEdge(dut.irq2)
        val = await read_int_flag(dut, 2)
        str_ = (await read_rx(dut, 2, 4)).hex()
        dut._log.info(f'idx2: flag: 0x{int(val):02x}, received: {str_}')
        if int(val) & 0x0f != BIT_FLAG_RX_BREAK | BIT_FLAG_RX_PENDING or str_ != '550301c5':
            dut._log.error(f'idx2: receive mismatch')
            await exit_err()

    dut._log.info('test_cdbus done.')
    await exit_ok()

