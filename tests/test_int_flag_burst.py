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

# CD_CHIP_SELECT: a burst read of INT_FLAG_L (INT_FLAG_L, RX_LEN, INT_FLAG_H) pulses csr_read
# once per byte with the same address; an event between the bytes must not be cleared
# by the later bytes, which only see the snapshot taken before the transfer.

from common import *

async def send_break(dut, sys_clk, factor): # start + 8 data + stop bits all low
    clk_period = 1000000000000 / sys_clk
    dut.bus_a.value = 0
    await Timer(11 * (factor + 1) * clk_period)
    dut.bus_a.value = 1
    await Timer(2 * (factor + 1) * clk_period)
    dut.bus_a.value = Logic('z')

# one csr_read pulse while the chip select is kept high
async def read_in_transfer(dut, idx, address):
    await RisingEdge(getattr(dut, f'clk{idx}'))
    getattr(dut, f'csr_addr{idx}').value = address
    getattr(dut, f'csr_read{idx}').value = 1
    await RisingEdge(getattr(dut, f'clk{idx}'))
    getattr(dut, f'csr_read{idx}').value = 0
    await ReadOnly()
    data = getattr(dut, f'csr_rdata{idx}').value
    await RisingEdge(getattr(dut, f'clk{idx}'))
    return data

@cocotb.test(timeout_time=2000, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')

    sys_clk = 40000000
    clk_period = 1000000000000 / sys_clk

    cocotb.start_soon(Clock(dut.clk0, clk_period).start())
    await reset(dut, 0)
    await check_version(dut, 0)

    await csr_write(dut, 0, REG_PIN_CFG, BIT_PIN_CFG_TX_PUSH_PULL)
    await set_div(dut, 0, 39, 39) # 1Mbps
    await Timer(50, unit='us') # let the bus become idle at the new baud rate

    await send_break(dut, sys_clk, 39) # break #1
    await Timer(15, unit='us')

    # transfer 1: 3-byte burst read of INT_FLAG_L, break #2 arrives between the bytes
    await RisingEdge(dut.clk0)
    dut.cs0.value = 1
    val0 = int((await read_in_transfer(dut, 0, REG_INT_FLAG_L))[7:0]) # low byte: the 32-bit version adds RX_LEN
    dut._log.info(f'idx0: INT_FLAG_L: 0x{val0:02x}')
    if not (val0 & BIT_FLAG_RX_BREAK):
        dut._log.error('idx0: break #1 not reported')
        await exit_err()
    await send_break(dut, sys_clk, 39) # break #2
    await Timer(2, unit='us')
    await read_in_transfer(dut, 0, REG_INT_FLAG_L) # RX_LEN
    await read_in_transfer(dut, 0, REG_INT_FLAG_L) # INT_FLAG_H
    await RisingEdge(dut.clk0)
    dut.cs0.value = 0
    await Timer(1, unit='us')

    # transfer 2: break #2 must still be there, and this read clears it
    val = int(await read_int_flag(dut, 0))
    dut._log.info(f'idx0: INT_FLAG_L: 0x{val:02x}')
    if not (val & BIT_FLAG_RX_BREAK):
        dut._log.error('idx0: break #2 lost, cleared by the later bytes of the burst')
        await exit_err()
    await Timer(1, unit='us')
    val = int(await read_int_flag(dut, 0))
    if val & BIT_FLAG_RX_BREAK:
        dut._log.error('idx0: break flag not cleared')
        await exit_err()

    dut._log.info('test_cdbus done.')
    await exit_ok()
