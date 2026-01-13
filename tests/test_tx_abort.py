# This Source Code Form is subject to the terms of the Mozilla
# Public License, v. 2.0. If a copy of the MPL was not distributed
# with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Notice: The scope granted to MPL excludes the ASIC industry.
#
# Copyright (c) 2017 DUKELEC, All rights reserved.
#
# Author: Duke Fong <d@d-l.io>
#

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

    await csr_write(dut, 0, REG_SETTING, 0b00010001)
    await csr_write(dut, 1, REG_SETTING, 0b00010001)
    await csr_write(dut, 1, REG_INT_MASK_L, 0b11001111)
    
    await set_div(dut, 0, 39, 2) # 1Mbps, 13.333Mbps
    await set_div(dut, 1, 39, 2)
    
    await csr_write(dut, 0, REG_FILTER, 0x01) # set local filter to 0x01
    await csr_write(dut, 1, REG_FILTER, 0x02) # set local filter to 0x02
    
    await write_tx(dut, 0, b'\x01\x02\x01\xcd') # node 0x01 send to 0x02
    await write_tx(dut, 0, b'\x01\x02\x01\x44') # node 0x01 send to 0x02
    #await csr_write(dut, 0, REG_CTRL, BIT_TX_START)
    dut.dbg0.value = 0
    
    await Timer(35, unit='us')
    dut.dbg0.value = 1
    await csr_write(dut, 0, REG_CTRL, BIT_TX_ABORT | BIT_TX_DROP)
    
    await write_tx(dut, 0, b'\x01\x02\x01\xc0') # node 0x01 send to 0x02
    #await csr_write(dut, 0, REG_CTRL, BIT_TX_START)

    await Timer(50, unit='us')
    dut.dbg1.value = 0
    val = await read_int_flag(dut, 1)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    str_ = (await read_rx(dut, 1, 4)).hex()
    dut._log.info(f'idx1: received: {str_}')
    if str_ != '010201c0':
        dut._log.error(f'idx1: receive mismatch')
        await exit_err()
    
    #await csr_write(dut, 1, REG_CTRL, BIT_RX_CLR_PENDING)
    await FallingEdge(dut.irq1)
    
    dut._log.info('test_cdbus done.')
    await exit_ok()

