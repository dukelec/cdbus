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

    await csr_write(dut, 0, REG_SETTING, BinaryValue('00010101')) # user crc
    await csr_write(dut, 1, REG_SETTING, BinaryValue('00011001')) # save broken frame
    await csr_write(dut, 1, REG_INT_MASK, BinaryValue('11011110'))
    
    await set_div(dut, 0, 39, 2) # 1Mbps, 13.333Mbps
    await set_div(dut, 1, 39, 2)
    
    await csr_write(dut, 0, REG_FILTER, 0x01) # set local filter to 0x01
    await csr_write(dut, 1, REG_FILTER, 0x02) # set local filter to 0x02
    
    await write_tx(dut, 0, b'\x01\x02\x01\xcd\x90\x91') # node 0x01 send to 0x02
    await csr_write(dut, 0, REG_TX_CTRL, BIT_TX_START)

    await RisingEdge(dut.irq1)
    val = await read_int_flag(dut, 1)
    rx_len = await read_rx_len(dut, 1)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}, rx len: 0x{int(rx_len):02x}')
    if val != 0x32:
        dut._log.error(f'idx1: wrong int_flag')
        await exit_err()
    
    str_ = (await read_rx(dut, 1, 6)).hex() # read 6 bytes (include crc)
    dut._log.info(f'idx1: received: {str_}')
    if str_ != '010201cd9091' or rx_len != 5: # frame len - 1
        dut._log.error(f'idx1: receive mismatch')
        await exit_err()
    
    await csr_write(dut, 1, REG_RX_CTRL, BIT_RX_CLR_PENDING)
    await FallingEdge(dut.irq1)
    
    
    await csr_write(dut, 1, REG_SETTING, BinaryValue('00010101')) # user crc
    
    await write_tx(dut, 0, b'\x01\x02\x01\xcd\x80\x81') # node 0x01 send to 0x02
    await csr_write(dut, 0, REG_TX_CTRL, BIT_TX_START)
    
    await RisingEdge(dut.irq1)
    val = await read_int_flag(dut, 1)
    rx_len = await read_rx_len(dut, 1)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}, rx len: 0x{int(rx_len):02x}')
    if val != 0x22:
        dut._log.error(f'idx1: wrong int_flag')
        await exit_err()
    
    str_ = (await read_rx(dut, 1, 6)).hex() # read 6 bytes (include crc)
    dut._log.info(f'idx1: received: {str_}')
    if str_ != '010201cd8081' or rx_len != 1: # user data len
        dut._log.error(f'idx1: receive mismatch')
        await exit_err()
    
    await csr_write(dut, 1, REG_RX_CTRL, BIT_RX_CLR_PENDING)
    await FallingEdge(dut.irq1)
    
    dut._log.info('test_cdbus done.')
    await exit_ok()

