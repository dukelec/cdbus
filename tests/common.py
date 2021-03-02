# This Source Code Form is subject to the terms of the Mozilla
# Public License, v. 2.0. If a copy of the MPL was not distributed
# with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Notice: The scope granted to MPL excludes the ASIC industry.
#
# Copyright (c) 2017 DUKELEC, All rights reserved.
#
# Author: Duke Fong <d@d-l.io>
#

import struct
import cocotb
from cocotb.binary import BinaryValue
from cocotb.triggers import RisingEdge, ReadOnly, Timer
from cocotb.clock import Clock

# pip3 install pythoncrc
from PyCRC.CRC16 import CRC16

def modbus_crc(data):
    return CRC16(modbus_flag=True).calculate(data).to_bytes(2, byteorder='little')

DFT_VERSION         = 0x0c

REG_VERSION         = 0x00
REG_SETTING         = 0x01
REG_IDLE_WAIT_LEN   = 0x02
REG_TX_PERMIT_LEN   = 0x03
REG_MAX_IDLE_LEN    = 0x04
REG_TX_PRE_LEN      = 0x05
REG_FILTER          = 0x06
REG_DIV_LS          = 0x07
REG_DIV_HS          = 0x08
REG_INT_FLAG        = 0x09
REG_INT_MASK        = 0x0a
REG_RX_CTRL         = 0x0b
REG_TX_CTRL         = 0x0c
REG_RX_PAGE_FLAG    = 0x0d
REG_FILTER_M        = 0x0e

BIT_SETTING_TX_PUSH_PULL    = 1 << 0
BIT_SETTING_TX_INVERT       = 1 << 1
BIT_SETTING_USER_CRC        = 1 << 2
BIT_SETTING_NO_DROP         = 1 << 3
BIT_SETTING_ARBITRATE       = 1 << 4
BIT_SETTING_BREAK_SYNC      = 1 << 5
BIT_SETTING_FULL_DUPLEX     = 1 << 6

BIT_FLAG_BUS_IDLE           = 1 << 0
BIT_FLAG_RX_PENDING         = 1 << 1
BIT_FLAG_RX_BREAK           = 1 << 2
BIT_FLAG_RX_LOST            = 1 << 3
BIT_FLAG_RX_ERROR           = 1 << 4
BIT_FLAG_TX_BUF_CLEAN       = 1 << 5
BIT_FLAG_TX_CD              = 1 << 6
BIT_FLAG_TX_ERROR           = 1 << 7

BIT_RX_RST_POINTER          = 1 << 0
BIT_RX_CLR_PENDING          = 1 << 1
BIT_RX_CLR_LOST             = 1 << 2
BIT_RX_CLR_ERROR            = 1 << 3
BIT_RX_RST                  = 1 << 4
BIT_RX_CLR_BREAK            = 1 << 5

BIT_TX_RST_POINTER          = 1 << 0
BIT_TX_START                = 1 << 1
BIT_TX_CLR_CD               = 1 << 2
BIT_TX_CLR_ERROR            = 1 << 3
BIT_TX_ABORT                = 1 << 4
BIT_TX_SEND_BREAK           = 1 << 5


async def _send_bytes(dut, bytes_, sys_clk, factor, is_z=True):
    clk_period = 1000000000000 / sys_clk
    await Timer(1000)
    factor += 1
    for byte in bytes_:
        dut.bus_a = 0
        await Timer(factor * clk_period)
        for i in range(0, 8):
            if byte & 0x01 == 0:
                dut.bus_a = 0
            else:
                dut.bus_a = BinaryValue('z') if is_z else 1
            await Timer(factor * clk_period)
            byte = byte >> 1
        dut.bus_a = BinaryValue('z') if is_z else 1
        await Timer(factor * clk_period)
        dut.bus_a = BinaryValue('z')

# Pass in a frame of data from the outside of the dut.
async def send_frame(dut, bytes_, sys_clk, factor_l, factor_h):
    await _send_bytes(dut, bytes_[0:1], sys_clk, factor_l)
    await _send_bytes(dut, bytes_[1:], sys_clk, factor_h, False)
    await _send_bytes(dut, modbus_crc(bytes_), sys_clk, factor_h, False)


async def reset(dut, idx, duration=10000):
    dut._log.debug(f'idx{idx}: resetting')
    setattr(dut, f'reset{idx}', 0)
    await Timer(duration)
    await RisingEdge(getattr(dut, f'clk{idx}'))
    setattr(dut, f'reset{idx}', 1)
    dut._log.debug(f'idx{idx}: out of reset')

async def csr_read(dut, idx, address, burst=False):
    addr_len = len(getattr(dut, f'csr_addr{idx}'))
    
    await RisingEdge(getattr(dut, f'clk{idx}'))
    setattr(dut, f'csr_addr{idx}', address)
    setattr(dut, f'csr_read{idx}', 1)
    
    await RisingEdge(getattr(dut, f'clk{idx}'))
    data = getattr(dut, f'csr_rdata{idx}').value
    setattr(dut, f'csr_read{idx}', 0)
    setattr(dut, f'csr_addr{idx}', BinaryValue('x' * addr_len))
    await ReadOnly()
    return data

async def csr_write(dut, idx, address, data, burst=False):
    addr_len = len(getattr(dut, f'csr_addr{idx}'))
    wdata_len = len(getattr(dut, f'csr_wdata{idx}'))
    
    await RisingEdge(getattr(dut, f'clk{idx}'))
    setattr(dut, f'csr_addr{idx}', address)
    setattr(dut, f'csr_byteenable{idx}', BinaryValue("1111"))
    setattr(dut, f'csr_wdata{idx}', data)
    setattr(dut, f'csr_write{idx}', 1)
    
    if not burst:
        await RisingEdge(getattr(dut, f'clk{idx}'))
        setattr(dut, f'csr_write{idx}', 0)
        setattr(dut, f'csr_addr{idx}', BinaryValue('x' * addr_len))
        setattr(dut, f'csr_wdata{idx}', BinaryValue('x' * wdata_len))

async def rx_mm_read(dut, idx, address):
    addr_len = len(getattr(dut, f'rx_mm_address{idx}'))
    
    await RisingEdge(getattr(dut, f'clk{idx}'))
    setattr(dut, f'rx_mm_address{idx}', address)
    setattr(dut, f'rx_mm_byteenable{idx}', BinaryValue("1111"))
    setattr(dut, f'rx_mm_read{idx}', 1)

    await RisingEdge(getattr(dut, f'clk{idx}'))
    setattr(dut, f'rx_mm_read{idx}', 0)
    setattr(dut, f'rx_mm_address{idx}', BinaryValue('x' * addr_len))
    await ReadOnly()
    data = getattr(dut, f'rx_mm_readdata{idx}').value
    return data

async def tx_mm_write(dut, idx, address, data, burst = False):
    addr_len = len(getattr(dut, f'rx_mm_address{idx}'))
    wdata_len = len(getattr(dut, f'tx_mm_writedata{idx}'))
    
    await RisingEdge(getattr(dut, f'clk{idx}'))
    setattr(dut, f'tx_mm_address{idx}', address)
    setattr(dut, f'tx_mm_byteenable{idx}', BinaryValue("1111"))
    setattr(dut, f'tx_mm_writedata{idx}', data)
    setattr(dut, f'tx_mm_write{idx}', 1)

    if not burst:
        await RisingEdge(getattr(dut, f'clk{idx}'))
        setattr(dut, f'tx_mm_write{idx}', 0)
        setattr(dut, f'tx_mm_address{idx}', BinaryValue('x' * addr_len))
        setattr(dut, f'tx_mm_writedata{idx}', BinaryValue('x' * wdata_len))


async def check_version(dut, idx):
    value = await csr_read(dut, idx, REG_VERSION)
    dut._log.info(f'idx{idx}: REG_VERSION: 0x%02x' % int(value))
    if value != DFT_VERSION:
        dut._log.error(f'idx{idx}: version mismatch')
        exit(-1)

async def set_div(dut, idx, div_ls, div_hs):
    await csr_write(dut, idx, REG_DIV_LS, div_ls)
    await csr_write(dut, idx, REG_DIV_HS, div_hs)

async def set_max_idle_len(dut, idx, max_idle_len):
    await csr_write(dut, idx, REG_MAX_IDLE_LEN, max_idle_len)

async def set_tx_permit_len(dut, idx, tx_permit_len):
    await csr_write(dut, idx, REG_TX_PERMIT_LEN, tx_permit_len)

async def write_tx(dut, idx, bytes_):
    if len(bytes_) == 0:
        return
    blk_cnt = int((len(bytes_)+3)/4)
    for i in range(blk_cnt):
        val = struct.unpack('<I', (bytes_[i*4 : i*4+4] + b'\x00\x00\x00')[0:4])[0]
        if i < blk_cnt - 1:
            await tx_mm_write(dut, idx, i, val, True)
        else:
            await tx_mm_write(dut, idx, i, val, False)

async def read_rx(dut, idx, len_):
    ret = b''
    if len_ == 0:
        return ret
    blk_cnt = int((len_+3)/4)
    left = len_%4
    for i in range(blk_cnt):
        val = await rx_mm_read(dut, idx, i)
        #dut._log.info('val:')
        #dut._log.info(val)
        if i == blk_cnt - 1 and left != 0:
            start = (4 - left) * 8
            val = val[start : 31]
        ret += struct.pack('<I', int(val))
    return ret[0: len_]


async def exit_err():
    await Timer(100, units='ns')
    exit(-1)

async def exit_ok():
    await Timer(10, units='us')
    with open('.exit_ok', 'w') as f:
        f.write('ok')

