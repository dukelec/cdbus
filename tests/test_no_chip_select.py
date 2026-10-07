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

# Build without CD_CHIP_SELECT (synchronous host, e.g. SoC bus) with CD_CSR_NO_LATENCY:
# pages are submitted and released through CTRL, DAT bursts are zero-wait-state.

from common import *

async def write_tx_submit(dut, idx, bytes_):
    for i in range(len(bytes_)):
        await csr_write(dut, idx, REG_DAT, bytes_[i], i < len(bytes_) - 1)
    await csr_write(dut, idx, REG_CTRL, BIT_TX_START)

async def wait_rx(dut, idx):
    while True:
        await Timer(1, unit='us')
        val = int(await read_int_flag(dut, idx))
        if val & BIT_FLAG_RX_PENDING:
            return val

@cocotb.test(timeout_time=2000, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')

    sys_clk = 40000000
    clk_period = 1000000000000 / sys_clk

    cocotb.start_soon(Clock(dut.clk0, clk_period).start())
    cocotb.start_soon(Clock(dut.clk1, clk_period).start())
    await reset(dut, 0)
    await reset(dut, 1)
    await check_version(dut, 0)
    await check_version(dut, 1)

    await csr_write(dut, 0, REG_PIN_CFG, BIT_PIN_CFG_TX_PUSH_PULL)
    await csr_write(dut, 1, REG_PIN_CFG, BIT_PIN_CFG_TX_PUSH_PULL)
    await set_div(dut, 0, 39, 2) # 1Mbps, 13.333Mbps
    await set_div(dut, 1, 39, 2)
    await csr_write(dut, 0, REG_FILTER, 0x01)
    await csr_write(dut, 1, REG_FILTER, 0x02)

    # frame 1: full read in one zero-wait-state burst, release by CTRL
    frame = b'\x01\x02\x05\x11\x22\x33\x44\x55'
    await write_tx_submit(dut, 0, frame)
    await wait_rx(dut, 1)
    rx_len = int(await read_rx_len(dut, 1))
    rx = await read_rx(dut, 1, rx_len + 3)
    dut._log.info(f'idx1: rx_len: {rx_len}, received: {rx.hex()}')
    if rx != frame:
        dut._log.error('idx1: receive mismatch')
        await exit_err()
    await csr_write(dut, 1, REG_CTRL, BIT_RX_CLR_PENDING)
    await Timer(1, unit='us')
    if int(await read_int_flag(dut, 1)) & BIT_FLAG_RX_PENDING:
        dut._log.error('idx1: page not released')
        await exit_err()

    # frame 2: the addresses were reset by CTRL; read in two bursts, the second after RX_ADDR
    frame = b'\x01\x02\x03\xaa\xbb\xcc'
    await write_tx_submit(dut, 0, frame)
    await wait_rx(dut, 1)
    rx = await read_rx(dut, 1, 2)
    await seek_rx(dut, 1, 3)
    rx += await read_rx(dut, 1, 3)
    dut._log.info(f'idx1: received: {rx.hex()}')
    if rx != frame[0:2] + frame[3:6]:
        dut._log.error('idx1: receive mismatch')
        await exit_err()
    await csr_write(dut, 1, REG_CTRL, BIT_RX_CLR_PENDING)

    dut._log.info('test_cdbus done.')
    await exit_ok()
