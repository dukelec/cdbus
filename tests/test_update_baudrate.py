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
    
    val = await csr_read(dut, 0, REG_SETTING)
    dut._log.info(f'idx0 REG_SETTING: 0x{int(val):02x}')

    await csr_write(dut, 0, REG_SETTING, BinaryValue('00010001'))
    await set_div(dut, 0, 79, 2)
    
    await Timer(4, units='us')
    while True:
        val = dut.cdbus_m0.cd_rx_des_m.cd_baud_rate_rx_m.cnt
        dut._log.info(f'idx0 baud cnt: {int(val)}')
        await Timer(50, units='ns')
        if int(val) > 50:
            break
    dut.dbg0 = 0
    await set_div(dut, 0, 39, 2)
    
    dut.dbg0 = 1
    val = dut.cdbus_m0.cd_rx_des_m.cd_baud_rate_rx_m.cnt
    dut._log.info(f'idx0 baud cnt after update: {int(val)}')
    if int(val) != 0:
        dut._log.error(f'baudrate is not updated in time')
        await exit_err()
    
    dut._log.info('test_cdbus done.')
    await exit_ok()

