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

# PIN_CFG bit1 (TX stays low for arbitration and break character): since TX_EN takes effect
# with a delay at the transceiver, TX must be low before and after a break as well.
# In bs mode, a node which sends in its slot, without having sent a break before, must send normal data.

from common import *

# tx_en and tx pin of a node, one sample per clock
async def record(dut, idx, n):
    pins = []
    for _ in range(n):
        await RisingEdge(getattr(dut, f'clk{idx}'))
        pins.append((int(getattr(dut, f'tx_en{idx}').value), int(getattr(dut, f'tx{idx}').value)))
    return pins

# tx low from `lead` clocks before the first tx_en pulse (None: all recorded) to `tail` clocks after it
async def check_low(dut, pins, lead, tail, what):
    en = [p[0] for p in pins]
    on = en.index(1)
    off = en.index(0, on)
    if lead is None:
        lead = on
    if on < lead or 1 in [p[1] for p in pins[on-lead:off+tail]]:
        dut._log.error(f'{what}: tx not low around tx_en (on at {on}, off at {off})')
        await exit_err()

@cocotb.test(timeout_time=500, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')

    sys_clk = 40000000
    clk_period = 1000000000000 / sys_clk

    for idx in [0, 1, 2]:
        cocotb.start_soon(Clock(getattr(dut, f'clk{idx}'), clk_period).start())
    for idx in [0, 1, 2]:
        await reset(dut, idx)

    for idx in [0, 1, 2]:
        await csr_write(dut, idx, REG_SETTING, BIT_SETTING_MODE_BS)
        await csr_write(dut, idx, REG_PIN_CFG, BIT_PIN_CFG_TX_PUSH_PULL | BIT_PIN_CFG_TX_KEEP_LOW)
        await set_max_idle_len(dut, idx, 40)
        await set_tx_permit_len(dut, idx, 10 + 10 * idx)
        await set_div(dut, idx, 2, 2)
    await csr_write(dut, 0, REG_FILTER, 0x55)
    await csr_write(dut, 1, REG_FILTER, 0xa5)
    await csr_write(dut, 2, REG_FILTER, 0x03)
    await csr_write(dut, 2, REG_INT_MASK_L, BIT_FLAG_RX_PENDING)
    await set_max_idle_len(dut, 2, 200) # its break below must go out in the slot

    await Timer(10, unit='us') # wait exceed max idle

    # node 0: break, then its frame
    rec = cocotb.start_soon(record(dut, 0, 60))
    await write_tx(dut, 0, b'\x55\x03\x01\xc5')
    await RisingEdge(dut.irq2)
    await check_low(dut, await rec, 3, 3, 'bs break') # one bit before and after
    # node 1: frame ready before its slot, no break
    await write_tx(dut, 1, b'\xa5\x03\x01\xca')

    val = int(await read_int_flag(dut, 2))
    if not (val & BIT_FLAG_RX_BREAK):
        dut._log.error('idx2: not receive break of node 0')
        await exit_err()
    str_ = (await read_rx(dut, 2, 4)).hex()
    if str_ != '550301c5':
        dut._log.error(f'idx2: receive mismatch first frame: {str_}')
        await exit_err()

    for _ in range(20):
        await Timer(1, unit='us')
        val = int(await read_int_flag(dut, 2))
        if val & (BIT_FLAG_RX_PENDING | BIT_FLAG_RX_BREAK | BIT_FLAG_RX_ERROR):
            break
    if (val & 0x0f) != BIT_FLAG_RX_PENDING:
        dut._log.error(f'idx2: node 1 not sent in its slot as data: flag 0x{val:02x}')
        await exit_err()
    str_ = (await read_rx(dut, 2, 4)).hex()
    if str_ != 'a50301ca':
        dut._log.error(f'idx2: receive mismatch second frame: {str_}')
        await exit_err()

    # node 2: break by CTRL, sent in its slot
    rec = cocotb.start_soon(record(dut, 2, 150))
    await csr_write(dut, 2, REG_CTRL, BIT_TX_SEND_BREAK)
    await check_low(dut, await rec, 3, 3, 'bs break in the slot')

    # arbitration mode after bs mode: tx is low all the time, also after the break by CTRL
    await csr_write(dut, 0, REG_SETTING, BIT_SETTING_MODE_ARBIT)
    await set_div(dut, 0, 9, 9)
    await Timer(20, unit='us')
    rec = cocotb.start_soon(record(dut, 0, 200))
    await csr_write(dut, 0, REG_CTRL, BIT_TX_SEND_BREAK)
    await check_low(dut, await rec, None, 200, 'arbitration break')

    dut._log.info('test_cdbus done.')
    await exit_ok()
