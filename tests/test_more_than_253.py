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

@cocotb.test(timeout_time=1500, timeout_unit='us')
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
    await csr_write(dut, 1, REG_INT_MASK_L, BinaryValue('11001111'))
    
    await set_div(dut, 0, 39, 2) # 1Mbps, 13.333Mbps
    await set_div(dut, 1, 39, 2) # 1Mbps, 13.333Mbps
    
    await csr_write(dut, 0, REG_FILTER, 0x01) # set local filter to 0x01
    await csr_write(dut, 1, REG_FILTER, 0x02) # set local filter to 0x02
    
    payload = b''
    for i in range(253+2):
        payload += bytes([i])
    dut._log.info(f'payload len: {len(payload)}')
    
    await Timer(50, units='us')
    await send_frame(dut, b'\x01\x02' + bytes([len(payload)]) + payload, sys_clk, 39, 2)
    tx_str_ = (b'\x01\x02' + bytes([len(payload)]) + payload).hex()
    dut._log.info(f'send_frame:   {tx_str_}')

    await RisingEdge(dut.irq1)
    val = await read_int_flag(dut, 1)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}')
    
    if not (val & BIT_FLAG_RX_ERROR):
        dut._log.error(f'idx1: not reveive rx_error')
        await exit_err()
    if val & BIT_FLAG_RX_PENDING:
        dut._log.error(f'idx1: should not rx pending')
        await exit_err()
    
    rx_str_ = (await read_rx(dut, 1, 256)).hex() # read 6 bytes (include crc)
    dut._log.info(f'idx1: rx ram: {rx_str_}  (not received)')
    if rx_str_ != tx_str_:
        dut._log.info(f'idx1: receive mismatch')
    
    
    
    await write_tx(dut, 0, b'\x01\x02' + bytes([len(payload)]) + payload) # node 0x01 send to 0x02
    #await csr_write(dut, 0, REG_CTRL, BIT_TX_START)
    await Timer(250, units='us')
    
    if IS_32BITS:
        rx_str_ = (await read_rx(dut, 1, 5)).hex() # read 5 bytes (include crc)
    else:
        rx_str_ = (await read_rx(dut, 1, 256)).hex() # read 256 bytes
    dut._log.info(f'idx1: rx ram: {rx_str_}  (not received)')
    
    dut._log.info('test_cdbus done.')
    await exit_ok()

