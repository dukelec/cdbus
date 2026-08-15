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
    
    val = await csr_read(dut, 0, REG_SETTING)
    dut._log.info(f'idx0 REG_SETTING: 0x{int(val):02x}')

    await csr_write(dut, 0, REG_SETTING, 0b00010001)
    await set_div(dut, 0, 79, 2)
    
    await Timer(4, unit='us')
    while True:
        val = dut.cdbus_m0.cd_rx_des_m.cd_baud_rate_rx_m.cnt.value
        dut._log.info(f'idx0 baud cnt: {int(val)}')
        await Timer(50, unit='ns')
        if int(val) > 50:
            break
    dut.dbg0.value = 0
    await set_div(dut, 0, 39, 2)
    
    dut.dbg0.value = 1
    val = dut.cdbus_m0.cd_rx_des_m.cd_baud_rate_rx_m.cnt.value
    dut._log.info(f'idx0 baud cnt after update: {int(val)}')
    if int(val) != 0:
        dut._log.error(f'baudrate is not updated in time')
        await exit_err()
    
    dut._log.info('test_cdbus done.')
    await exit_ok()

