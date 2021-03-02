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
    
    val = await csr_read(dut, 0, REG_SETTING, False)
    dut._log.info(f'idx0 REG_SETTING: 0x{int(val):02x}')

    await csr_write(dut, 0, REG_SETTING, BinaryValue('00100001')) # bs mode
    await csr_write(dut, 1, REG_SETTING, BinaryValue('00100001'))
    await csr_write(dut, 2, REG_SETTING, BinaryValue('00100001'))
    await csr_write(dut, 2, REG_INT_MASK, BinaryValue('11011010')) # not select break rx
    
    await set_max_idle_len(dut, 0, 40)
    await set_max_idle_len(dut, 1, 40)
    await set_max_idle_len(dut, 2, 40)
    
    await set_tx_permit_len(dut, 0, 10)
    await set_tx_permit_len(dut, 1, 20)
    await set_tx_permit_len(dut, 2, 30)

    await set_div(dut, 0, 2, 2) # max speed
    await set_div(dut, 1, 2, 2)
    await set_div(dut, 2, 2, 2)
    
    await csr_write(dut, 0, REG_FILTER, 0x55)
    await csr_write(dut, 1, REG_FILTER, 0xa5)
    await csr_write(dut, 2, REG_FILTER, 0x03)
    
    
    await Timer(10, units='us') # wait exceed max idle
    
    await write_tx(dut, 0, b'\x55\x03\x01\xc5') # node 0x55 send to 0x03
    await write_tx(dut, 1, b'\xa5\x03\x01\xca') # node 0xa5 send to 0x03
    
    # start tx at same time
    cocotb.fork(csr_write(dut, 0, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER))
    cocotb.fork(csr_write(dut, 1, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER))

    await RisingEdge(dut.irq2)
    val = await csr_read(dut, 2, REG_INT_FLAG)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    if not (val & BIT_FLAG_RX_BREAK):
        dut._log.error(f'idx2: not receive break')
        await exit_err()
    
    str_ = (await read_rx(dut, 2, 4)).hex() # read 4 bytes
    dut._log.info(f'idx2: received: {str_}')
    if str_ != '550301c5':
        dut._log.error(f'idx2: receive mismatch first frame')
        await exit_err()
    
    await csr_write(dut, 2, REG_RX_CTRL, BIT_RX_CLR_PENDING | BIT_RX_RST_POINTER)
    await Timer(500, units='ns')
    
    await RisingEdge(dut.irq2)
    val = await csr_read(dut, 2, REG_INT_FLAG)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    str_ = (await read_rx(dut, 2, 4)).hex() # read 4 bytes
    dut._log.info(f'idx2: received: {str_}')
    if str_ != 'a50301ca':
        dut._log.error(f'idx2: receive mismatch second frame')
        await exit_err()
    
    await csr_write(dut, 2, REG_RX_CTRL, BIT_RX_CLR_PENDING | BIT_RX_RST_POINTER)
    await FallingEdge(dut.irq2)
    
    
    await Timer(10, units='us') # wait exceed max idle
    
    await write_tx(dut, 0, b'\x55\x03\x01\xc5') # node 0x55 send to 0x03
    await write_tx(dut, 1, b'\xa5\x03\x01\xca') # node 0xa5 send to 0x03
    
    cocotb.fork(csr_write(dut, 1, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER))
    dut.dbg0 = 0
    await Timer(2700, units='ns') # wait frame pending after tx permit
    dut.dbg0 = 1
    cocotb.fork(csr_write(dut, 0, REG_TX_CTRL, BIT_TX_START | BIT_TX_RST_POINTER))
    
    await RisingEdge(dut.irq2)
    val = await csr_read(dut, 2, REG_INT_FLAG)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    if not (val & BIT_FLAG_RX_BREAK):
        dut._log.error(f'idx2: not receive break')
        await exit_err()
    
    str_ = (await read_rx(dut, 2, 4)).hex() # read 4 bytes
    dut._log.info(f'idx2: received: {str_}')
    if str_ != 'a50301ca':
        dut._log.error(f'idx2: receive mismatch first frame')
        await exit_err()
    
    await csr_write(dut, 2, REG_RX_CTRL, BIT_RX_CLR_PENDING | BIT_RX_RST_POINTER)
    await Timer(500, units='ns')
    
    await RisingEdge(dut.irq2)
    val = await csr_read(dut, 2, REG_INT_FLAG)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    str_ = (await read_rx(dut, 2, 4)).hex() # read 4 bytes
    dut._log.info(f'idx2: received: {str_}')
    if str_ != '550301c5':
        dut._log.error(f'idx2: receive mismatch second frame')
        await exit_err()
    
    await csr_write(dut, 2, REG_RX_CTRL, BIT_RX_CLR_PENDING | BIT_RX_RST_POINTER)
    await FallingEdge(dut.irq2)
    
    dut._log.info('test_cdbus done.')
    await exit_ok()

