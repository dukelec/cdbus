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

# The TX path must get in step again by itself after one flipped register bit:
# the wait flags of cd_tx_ser on an idle bus, and the page pointers of cd_tx_ram.
# Also: TX_PERMIT_LEN may be longer than MAX_IDLE_LEN outside of bs mode.

from common import *

async def wait_rx(dut, idx, us):
    for _ in range(us):
        await Timer(1, unit='us')
        if int(await read_int_flag(dut, idx)) & BIT_FLAG_RX_PENDING:
            return True
    return False

# node 0 sends one frame, node 1 must get it before anything else is sent
async def send_check(dut, tag, what):
    frame = b'\x01\x02\x01' + bytes([tag])
    await write_tx(dut, 0, frame)
    if not await wait_rx(dut, 1, 30):
        dut._log.error(f'{what}: frame {tag:02x} not sent')
        await exit_err()
    rx = await read_rx(dut, 1, 4)
    if rx != frame:
        dut._log.error(f'{what}: received {rx.hex()}, expected {frame.hex()}')
        await exit_err()

# let node 0 send whatever it holds, drop what node 1 got
async def settle(dut):
    await Timer(30, unit='us')
    while int(await read_int_flag(dut, 1)) & BIT_FLAG_RX_PENDING:
        await read_rx(dut, 1, 4)
        await Timer(1, unit='us')

@cocotb.test(timeout_time=2000, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')

    sys_clk = 40000000
    clk_period = 1000000000000 / sys_clk

    cocotb.start_soon(Clock(dut.clk0, clk_period).start())
    cocotb.start_soon(Clock(dut.clk1, clk_period).start())
    await reset(dut, 0)
    await reset(dut, 1)

    for idx in [0, 1]:
        await csr_write(dut, idx, REG_SETTING, BIT_SETTING_MODE_HALF)
        await csr_write(dut, idx, REG_PIN_CFG, BIT_PIN_CFG_TX_PUSH_PULL)
        await set_div(dut, idx, 2, 2)
        await set_max_idle_len(dut, idx, 40)
    await csr_write(dut, 0, REG_FILTER, 0x01)
    await csr_write(dut, 1, REG_FILTER, 0x02)
    tx_ser = dut.cdbus_m0.cd_tx_ser_m
    tx_ram = dut.cdbus_m0.cd_tx_ram_m

    await send_check(dut, 0x10, 'no fault')
    await send_check(dut, 0x11, 'no fault') # both tx pages hold a frame now

    await set_tx_permit_len(dut, 0, 60)
    await send_check(dut, 0x20, 'permit len > max idle len')
    await set_tx_permit_len(dut, 0, 20)

    await Timer(10, unit='us')
    if int(tx_ser.reach_max_idle.value) != 1 or int(tx_ser.tx_permit_d.value) != 3:
        dut._log.error('max idle not reached')
        await exit_err()
    await RisingEdge(dut.clk0)
    tx_ser.tx_permit_d.value = 0
    await send_check(dut, 0x30, 'tx_permit_d flipped')

    tag = 0x40
    for name, val in [('rd_sel', None), ('unread_cnt', 1), ('unread_cnt', 2), ('unread_cnt', 3)]:
        await Timer(10, unit='us')
        sig = getattr(tx_ram, name)
        await RisingEdge(dut.clk0)
        sig.value = (1 - int(sig.value)) if val is None else val
        await settle(dut) # a stale page may be sent
        for _ in range(3):
            await send_check(dut, tag, f'{name} flipped')
            tag += 1

    dut._log.info('test_cdbus done.')
    await exit_ok()
