# This Source Code Form is subject to the terms of the Mozilla
# Public License, v. 2.0. If a copy of the MPL was not distributed
# with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Notice: The scope granted to MPL excludes the ASIC industry.
#
# Copyright (c) 2017 DUKELEC, All rights reserved.
#
# Author: Duke Fong <d@d-l.io>
#

import importlib
import cocotb
from cocotb.binary import BinaryValue
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly, Timer
from cocotb.clock import Clock
from common import *

@cocotb.test(timeout_time=500, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')
    
    sys_clk = 40000000
    clk_period = 1000000000000 / sys_clk

    cocotb.fork(Clock(dut.clk0, clk_period).start())
    cocotb.fork(Clock(dut.clk1, clk_period).start())
    cocotb.fork(Clock(dut.clk2, clk_period).start())
    await reset(dut, 0)
    await reset(dut, 1)
    await reset(dut, 2)
    await check_version(dut, 0)
    await check_version(dut, 1)
    await check_version(dut, 2)
    
    val = await csr_read(dut, 0, REG_SETTING)
    dut._log.info(f'idx0 REG_SETTING: 0x{int(val):02x}')

    await csr_write(dut, 0, REG_SETTING, BinaryValue('00010001'))
    await csr_write(dut, 1, REG_SETTING, BinaryValue('00010001'))
    await csr_write(dut, 1, REG_INT_MASK, BinaryValue('11011110'))
    
    await set_div(dut, 0, 39, 2) # 1Mbps, 13.333Mbps
    await set_div(dut, 1, 39, 2)
    
    await csr_write(dut, 0, REG_FILTER, 0x01) # set local filter to 0x01
    await csr_write(dut, 1, REG_FILTER, 0x02) # set local filter to 0x02
    await csr_write(dut, 1, REG_FILTER1, 0xe0) # set mcast filter
    
    await write_tx(dut, 0, b'\x01\xe0\x01\xcd')
    await csr_write(dut, 0, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER)

    await RisingEdge(dut.irq1)
    val = await csr_read(dut, 1, REG_INT_FLAG)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    str_ = (await read_rx(dut, 1, 4)).hex()
    dut._log.info(f'idx1: received: {str_}')
    if str_ != '01e001cd':
        dut._log.error(f'idx1: receive mismatch')
        await exit_err()
    
    await csr_write(dut, 1, REG_RX_CTRL, BIT_RX_CLR_PENDING | BIT_RX_RST_POINTER)
    await FallingEdge(dut.irq1)
    
    # test another maddr
    await csr_write(dut, 1, REG_FILTER2, 0xe1) # set mcast filter
    
    await write_tx(dut, 0, b'\x01\xe1\x01\xcd')
    await csr_write(dut, 0, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER)

    await RisingEdge(dut.irq1)
    val = await csr_read(dut, 1, REG_INT_FLAG)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    str_ = (await read_rx(dut, 1, 4)).hex()
    dut._log.info(f'idx1: received: {str_}')
    if str_ != '01e101cd':
        dut._log.error(f'idx1: receive mismatch')
        await exit_err()
    
    await csr_write(dut, 1, REG_RX_CTRL, BIT_RX_CLR_PENDING | BIT_RX_RST_POINTER)
    await FallingEdge(dut.irq1)
    
    
    # test broadcast when all mcast addr in use
    await write_tx(dut, 0, b'\x01\xff\x01\xcd')
    await csr_write(dut, 0, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER)

    await RisingEdge(dut.irq1)
    val = await csr_read(dut, 1, REG_INT_FLAG)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    str_ = (await read_rx(dut, 1, 4)).hex()
    dut._log.info(f'idx1: received: {str_}')
    if str_ != '01ff01cd':
        dut._log.error(f'idx1: receive mismatch')
        await exit_err()
    
    await csr_write(dut, 1, REG_RX_CTRL, BIT_RX_CLR_PENDING | BIT_RX_RST_POINTER)
    await FallingEdge(dut.irq1)
    
    # test not receive
    await write_tx(dut, 0, b'\x01\xf0\x01\xcd')
    await csr_write(dut, 0, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER)

    await Timer(60, units='us')
    dut.dbg0 = 1
    if dut.irq1 != 0:
        dut._log.error(f'idx1: should not receive')
        await exit_err()
    
    dut._log.info('test_cdbus done.')
    await exit_ok()

