# This Source Code Form is subject to the terms of the Mozilla
# Public License, v. 2.0. If a copy of the MPL was not distributed
# with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Notice: The scope granted to MPL excludes the ASIC industry.
#
# Copyright (c) 2017 DUKELEC, All rights reserved.
#
# Author: Duke Fong <d@d-l.io>
#

import cocotb
from cocotb.types import Logic, LogicArray
from cocotb.triggers import RisingEdge, ReadOnly, Timer
from cocotb.clock import Clock

# pip3 install pythoncrc
from PyCRC.CRC16 import CRC16

def modbus_crc(data):
    return CRC16(modbus_flag=True).calculate(data).to_bytes(2, byteorder='little')


DFT_VERSION         = 0x0f

REG_VERSION         = 0x00
REG_SETTING         = 0x02
REG_IDLE_WAIT_LEN   = 0x04
REG_TX_PERMIT_LEN_L = 0x05
REG_TX_PERMIT_LEN_H = 0x06
REG_MAX_IDLE_LEN_L  = 0x07
REG_MAX_IDLE_LEN_H  = 0x08
REG_TX_PRE_LEN      = 0x09
REG_FILTER          = 0x0b
REG_DIV_LS_L        = 0x0c
REG_DIV_LS_H        = 0x0d
REG_DIV_HS_L        = 0x0e
REG_DIV_HS_H        = 0x0f
REG_INT_MASK_L      = 0x10
REG_INT_MASK_H      = 0x11
REG_INT_FLAG_L      = 0x12
REG_INT_FLAG_H      = 0x13
REG_RX_LEN          = 0x14
REG_DAT             = 0x15
REG_CTRL            = 0x16
REG_FILTER_M0       = 0x1a
REG_FILTER_M1       = 0x1b
REG_FILTER_MSK0     = 0x1c
REG_FILTER_MSK1     = 0x1d

BIT_SETTING_RX_INVERT       = 1 << 6
BIT_SETTING_NO_DROP         = 1 << 3
BIT_SETTING_USER_CRC        = 1 << 2
BIT_SETTING_TX_INVERT       = 1 << 1
BIT_SETTING_TX_PUSH_PULL    = 1 << 0

BIT_FLAG_TX_ERROR           = 1 << 7
BIT_FLAG_TX_CD              = 1 << 6
BIT_FLAG_TX_BUF_CLEAN       = 1 << 5
BIT_FLAG_TX_BUF_FREE        = 1 << 4
BIT_FLAG_RX_ERROR           = 1 << 3
BIT_FLAG_RX_LOST            = 1 << 2
BIT_FLAG_RX_BREAK           = 1 << 1
BIT_FLAG_RX_PENDING         = 1 << 0

BIT_RX_RST                  = 1 << 7
BIT_RX_CLR_PENDING          = 1 << 4
BIT_TX_ABORT                = 1 << 3
BIT_TX_DROP                 = 1 << 2
BIT_TX_SEND_BREAK           = 1 << 1
BIT_TX_START                = 1 << 0


async def _send_bytes(dut, bytes_, sys_clk, factor, is_z=True):
    clk_period = 1000000000000 / sys_clk
    await Timer(1000)
    factor += 1
    for byte in bytes_:
        dut.bus_a.value = 0
        await Timer(factor * clk_period)
        for i in range(0, 8):
            if byte & 0x01 == 0:
                dut.bus_a.value = 0
            else:
                dut.bus_a.value = Logic('z') if is_z else 1
            await Timer(factor * clk_period)
            byte = byte >> 1
        dut.bus_a.value = Logic('z') if is_z else 1
        await Timer(factor * clk_period)
        dut.bus_a.value = Logic('z')

# Pass in a frame of data from the outside of the dut.
async def send_frame(dut, bytes_, sys_clk, factor_l, factor_h):
    await _send_bytes(dut, bytes_[0:1], sys_clk, factor_l)
    await _send_bytes(dut, bytes_[1:], sys_clk, factor_h, False)
    await _send_bytes(dut, modbus_crc(bytes_), sys_clk, factor_h, False)


async def exit_err():
    await Timer(1000, unit='ns')
    exit(-1)

async def exit_ok():
    await Timer(10, unit='us')
    with open('.exit_ok', 'w') as f:
        f.write('ok')

