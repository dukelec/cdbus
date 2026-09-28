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

# Access one TX / RX page across multiple chip-select transfers through DAT_HOLD.

from common import *

@cocotb.test(timeout_time=500, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')

    sys_clk = 40000000
    clk_period = 1000000000000 / sys_clk

    cocotb.start_soon(Clock(dut.clk0, clk_period).start())
    cocotb.start_soon(Clock(dut.clk1, clk_period).start())
    cocotb.start_soon(Clock(dut.clk2, clk_period).start())
    await reset(dut, 0)
    await reset(dut, 1)
    await reset(dut, 2)
    await check_version(dut, 0)
    await check_version(dut, 1)

    await csr_write(dut, 0, REG_SETTING, 0b00010001)
    await csr_write(dut, 1, REG_SETTING, 0b00010001)
    await csr_write(dut, 1, REG_INT_MASK_L, 0b11001111)

    await set_div(dut, 0, 39, 2) # 1Mbps, 13.333Mbps
    await set_div(dut, 1, 39, 2)

    await csr_write(dut, 0, REG_FILTER, 0x01)
    await csr_write(dut, 1, REG_FILTER, 0x02)

    payload = bytes(range(0x10, 0x1a))
    tx_pkt = b'\x01\x02' + bytes([len(payload)]) + payload
    expect = (tx_pkt + modbus_crc(tx_pkt)).hex()

    # --- TX: two parts through DAT_HOLD, last part through DAT (auto submit) ---
    await write_tx(dut, 0, tx_pkt[0:3], REG_DAT_HOLD)
    val = await read_int_flag(dut, 0) # unrelated transfer in between must not disturb
    dut._log.info(f'idx0 REG_INT_FLAG: 0x{int(val):02x}')
    if int(val) & BIT_FLAG_TX_BUF_CLEAN == 0:
        dut._log.error('idx0: TX page submitted too early')
        await exit_err()
    await write_tx(dut, 0, tx_pkt[3:8], REG_DAT_HOLD)
    await Timer(5, unit='us')
    if dut.tx_en0.value != 0: # nothing should be sent yet
        dut._log.error('idx0: bus not idle before submit')
        await exit_err()
    await write_tx(dut, 0, tx_pkt[8:], REG_DAT)

    await RisingEdge(dut.irq1)
    val, len_, _ = await read_int_flag3(dut, 1)
    dut._log.info(f'idx1 REG_INT_FLAG: 0x{int(val):02x}, len: {int(len_)}')

    # --- RX: read in three parts through DAT_HOLD, last part through DAT (auto release) ---
    total = int(len_) + 5
    str_ = (await read_rx(dut, 1, 4, REG_DAT_HOLD)).hex()
    val = await read_int_flag(dut, 1)
    if int(val) & BIT_FLAG_RX_PENDING == 0:
        dut._log.error('idx1: RX page released too early')
        await exit_err()
    str_ += (await read_rx(dut, 1, 5, REG_DAT_HOLD)).hex()
    str_ += (await read_rx(dut, 1, total - 9, REG_DAT)).hex()
    dut._log.info(f'idx1: received: {str_}')
    if str_ != expect:
        dut._log.error(f'idx1: receive mismatch, expect: {expect}')
        await exit_err()
    await FallingEdge(dut.irq1)

    # --- TX: all through DAT_HOLD, then manual submit by CTRL ---
    payload = bytes(range(0x20, 0x27))
    tx_pkt = b'\x01\x02' + bytes([len(payload)]) + payload
    expect = (tx_pkt + modbus_crc(tx_pkt)).hex()

    await write_tx(dut, 0, tx_pkt[0:4], REG_DAT_HOLD)
    await write_tx(dut, 0, tx_pkt[4:], REG_DAT_HOLD)
    await Timer(5, unit='us')
    if dut.tx_en0.value != 0:
        dut._log.error('idx0: bus not idle before manual submit')
        await exit_err()
    await csr_write(dut, 0, REG_CTRL, BIT_TX_START)

    await RisingEdge(dut.irq1)
    val, len_, _ = await read_int_flag3(dut, 1)
    dut._log.info(f'idx1 REG_INT_FLAG: 0x{int(val):02x}, len: {int(len_)}')

    # --- RX: all through DAT_HOLD, then manual release by CTRL ---
    total = int(len_) + 5
    str_ = (await read_rx(dut, 1, 1, REG_DAT_HOLD)).hex() # single byte transfer
    str_ += (await read_rx(dut, 1, total - 1, REG_DAT_HOLD)).hex()
    dut._log.info(f'idx1: received: {str_}')
    if str_ != expect:
        dut._log.error(f'idx1: receive mismatch, expect: {expect}')
        await exit_err()
    val = await read_int_flag(dut, 1)
    if int(val) & BIT_FLAG_RX_PENDING == 0:
        dut._log.error('idx1: RX page released without CTRL')
        await exit_err()
    await csr_write(dut, 1, REG_CTRL, BIT_RX_CLR_PENDING)
    await FallingEdge(dut.irq1)

    # --- back to normal: single transfer through DAT still works after hold usage ---
    tx_pkt = b'\x01\x02\x01\xcd'
    expect = (tx_pkt + modbus_crc(tx_pkt)).hex()
    await write_tx(dut, 0, tx_pkt)
    await RisingEdge(dut.irq1)
    str_ = (await read_rx(dut, 1, 6)).hex()
    dut._log.info(f'idx1: received: {str_}')
    if str_ != expect:
        dut._log.error(f'idx1: receive mismatch, expect: {expect}')
        await exit_err()
    await FallingEdge(dut.irq1)

    dut._log.info('test_cdbus done.')
    await exit_ok()
