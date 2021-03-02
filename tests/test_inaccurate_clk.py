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
    
    sys_clk0 = 40000000
    clk_period0 = round(1000000000000 / sys_clk0)
    sys_clk1 = 38801800
    clk_period1 = round(1000000000000 / sys_clk1)

    cocotb.fork(Clock(dut.clk0, clk_period0).start())
    cocotb.fork(Clock(dut.clk1, clk_period1).start())
    await reset(dut, 0)
    await reset(dut, 1)
    await check_version(dut, 0)
    await check_version(dut, 1)
    
    val = await csr_read(dut, 0, REG_SETTING)
    dut._log.info(f'idx0 REG_SETTING: 0x{int(val):02x}')

    await csr_write(dut, 0, REG_SETTING, BinaryValue('00010001'))
    await csr_write(dut, 1, REG_SETTING, BinaryValue('00010001'))
    await csr_write(dut, 0, REG_INT_MASK, BinaryValue('11011110'))
    await csr_write(dut, 1, REG_INT_MASK, BinaryValue('11011110'))
    
    await set_div(dut, 0, 39, 2) # 1Mbps, 13.333Mbps
    await set_div(dut, 1, 39, 2)
    
    await csr_write(dut, 0, REG_FILTER, 0x01) # set local filter to 0x01
    await csr_write(dut, 1, REG_FILTER, 0x02) # set local filter to 0x02
    
    payload = b''
    for i in range(253):
        payload += bytes([i])
    dut._log.info(f'payload len: {len(payload)}')
    
    await write_tx(dut, 0, b'\x01\x02' + bytes([len(payload)]) + payload) # node 0x01 send to 0x02
    await csr_write(dut, 0, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER)
    
    await write_tx(dut, 1, b'\x02\x01' + bytes([len(payload)]) + payload) # node 0x01 send to 0x02
    await csr_write(dut, 1, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER)

    await RisingEdge(dut.irq1)
    val = await csr_read(dut, 1, REG_INT_FLAG)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    ret = await read_rx(dut, 1, 256)
    str_ = ret[0:3].hex()
    dut._log.info(f'ret: {ret.hex()}')
    dut._log.info(f'idx1: received: {str_}, last: 0x{ret[-1]:02x}')
    if str_ != '0102fd' or ret[-1] != 0xfc:
        dut._log.error(f'idx1: receive mismatch')
        await exit_err()
    
    await csr_write(dut, 1, REG_RX_CTRL, BIT_RX_CLR_PENDING | BIT_RX_RST_POINTER)
    await FallingEdge(dut.irq1)
    
    await RisingEdge(dut.irq0)
    val = await csr_read(dut, 0, REG_INT_FLAG)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    ret = await read_rx(dut, 0, 256)
    str_ = ret[0:3].hex()
    dut._log.info(f'ret: {ret.hex()}')
    dut._log.info(f'idx0: received: {str_}, last: 0x{ret[-1]:02x}')
    if str_ != '0201fd' or ret[-1] != 0xfc:
        dut._log.error(f'idx0: receive mismatch')
        await exit_err()
    
    await csr_write(dut, 0, REG_RX_CTRL, BIT_RX_CLR_PENDING | BIT_RX_RST_POINTER)
    await FallingEdge(dut.irq0)
    
    dut._log.info('test_cdbus done.')
    await exit_ok()

