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

    cocotb.start_soon(Clock(dut.clk0, clk_period).start())
    cocotb.start_soon(Clock(dut.clk1, clk_period).start())
    cocotb.start_soon(Clock(dut.clk2, clk_period).start())
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
    await csr_write(dut, 2, REG_SETTING, BinaryValue('00010001'))
    await csr_write(dut, 2, REG_INT_MASK, BinaryValue('11011110'))

    await set_div(dut, 0, 39, 2) # 1Mbps, 13.333Mbps
    await set_div(dut, 1, 39, 2) # 1Mbps, 13.333Mbps
    await set_div(dut, 2, 39, 2) # 1Mbps, 13.333Mbps
    
    await csr_write(dut, 0, REG_FILTER, 0x55) # set local filter to 0x55
    await csr_write(dut, 1, REG_FILTER, 0xa5) # set local filter to 0xa5
    await csr_write(dut, 2, REG_FILTER, 0x03) # set local filter to 0x03
    
    await write_tx(dut, 0, b'\x55\x03\x01\xc5') # node 0x55 send to 0x03
    await write_tx(dut, 1, b'\xa5\x03\x01\xca') # node 0xa5 send to 0x03
    
    # start tx at same time
    cocotb.start_soon(csr_write(dut, 0, REG_TX_CTRL, BIT_TX_START))
    cocotb.start_soon(csr_write(dut, 1, REG_TX_CTRL, BIT_TX_START))

    await RisingEdge(dut.irq2)
    val = await read_int_flag(dut, 2)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    str_ = (await read_rx(dut, 2, 4)).hex() # read 4 bytes
    dut._log.info(f'idx2: received: {str_}')
    if str_ != 'a50301ca':
        dut._log.error(f'idx2: receive mismatch first frame')
        await exit_err()
    
    await csr_write(dut, 2, REG_RX_CTRL, BIT_RX_CLR_PENDING)
    await Timer(500, units='ns')
    
    await RisingEdge(dut.irq2)
    val = await read_int_flag(dut, 2)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    str_ = (await read_rx(dut, 2, 4)).hex() # read 4 bytes
    dut._log.info(f'idx2: received: {str_}')
    if str_ != '550301c5':
        dut._log.error(f'idx2: receive mismatch second frame')
        await exit_err()
    
    await csr_write(dut, 2, REG_RX_CTRL, BIT_RX_CLR_PENDING)
    await FallingEdge(dut.irq2)
    
    dut._log.info('test_cdbus done.')
    await exit_ok()

