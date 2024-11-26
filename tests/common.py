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

IS_32BITS           = True

DFT_VERSION         = 0x0f

REG_VERSION         = 0x00
REG_SETTING         = 0x01
REG_IDLE_WAIT_LEN   = 0x02
REG_TX_PERMIT_LEN   = 0x03
REG_MAX_IDLE_LEN    = 0x04
REG_TX_PRE_LEN      = 0x05
REG_FILTER          = 0x06
REG_DIV_LS          = 0x07
REG_DIV_HS          = 0x08
REG_INT_MASK        = 0x09
REG_INT_FLAG        = 0x0a
REG_RX              = 0x0b
REG_TX              = 0x0c
REG_RX_CTRL         = 0x0d
REG_TX_CTRL         = 0x0e
REG_FILTER_M        = 0x0f

BIT_SETTING_IDLE_INVERT     = 1 << 7
BIT_SETTING_RX_INVERT       = 1 << 6
BIT_SETTING_NO_DROP         = 1 << 3
BIT_SETTING_USER_CRC        = 1 << 2
BIT_SETTING_TX_INVERT       = 1 << 1
BIT_SETTING_TX_PUSH_PULL    = 1 << 0

BIT_FLAG_TX_ERROR           = 1 << 7
BIT_FLAG_TX_CD              = 1 << 6
BIT_FLAG_TX_BUF_CLEAN       = 1 << 5
BIT_FLAG_RX_ERROR           = 1 << 4
BIT_FLAG_RX_LOST            = 1 << 3
BIT_FLAG_RX_BREAK           = 1 << 2
BIT_FLAG_RX_PENDING         = 1 << 1
BIT_FLAG_BUS_IDLE           = 1 << 0

BIT_RX_RST                  = 1 << 4
BIT_RX_CLR_PENDING          = 1 << 1

BIT_TX_SEND_BREAK           = 1 << 5
BIT_TX_ABORT                = 1 << 4
BIT_TX_START                = 1 << 1


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
                dut.bus_a.value = BinaryValue('z') if is_z else 1
            await Timer(factor * clk_period)
            byte = byte >> 1
        dut.bus_a.value = BinaryValue('z') if is_z else 1
        await Timer(factor * clk_period)
        dut.bus_a.value = BinaryValue('z')

# Pass in a frame of data from the outside of the dut.
async def send_frame(dut, bytes_, sys_clk, factor_l, factor_h):
    await _send_bytes(dut, bytes_[0:1], sys_clk, factor_l)
    await _send_bytes(dut, bytes_[1:], sys_clk, factor_h, False)
    await _send_bytes(dut, modbus_crc(bytes_), sys_clk, factor_h, False)


async def reset(dut, idx, duration=10000):
    dut._log.debug(f'idx{idx}: resetting')
    getattr(dut, f'reset{idx}').value = 0
    await Timer(duration)
    await RisingEdge(getattr(dut, f'clk{idx}'))
    getattr(dut, f'reset{idx}').value = 1
    dut._log.debug(f'idx{idx}: out of reset')
    getattr(dut, f'cs{idx}').value = 0

async def csr_read(dut, idx, address, burst=False, burst_end=False):
    addr_len = len(getattr(dut, f'csr_addr{idx}'))
    
    await RisingEdge(getattr(dut, f'clk{idx}'))
    getattr(dut, f'cs{idx}').value = 1
    getattr(dut, f'csr_addr{idx}').value = address
    getattr(dut, f'csr_read{idx}').value = 1
    if burst_end:
        getattr(dut, f'csr_read{idx}').value = 0
    await ReadOnly()
    data = getattr(dut, f'csr_rdata{idx}').value
    if not burst:
        await RisingEdge(getattr(dut, f'clk{idx}'))
        getattr(dut, f'csr_read{idx}').value = 0
        getattr(dut, f'csr_addr{idx}').value = BinaryValue('x' * addr_len)
        getattr(dut, f'cs{idx}').value = 0
    return data

async def csr_write(dut, idx, address, data, burst=False):
    addr_len = len(getattr(dut, f'csr_addr{idx}'))
    wdata_len = len(getattr(dut, f'csr_wdata{idx}'))
    if isinstance(data, BinaryValue): # padding to 32 bits
        data = BinaryValue(value=int(data), n_bits=32, bigEndian=False)
    
    await RisingEdge(getattr(dut, f'clk{idx}'))
    getattr(dut, f'cs{idx}').value = 1
    getattr(dut, f'csr_addr{idx}').value = address
    getattr(dut, f'csr_wdata{idx}').value = data
    getattr(dut, f'csr_write{idx}').value = 1
    if not burst:
        await RisingEdge(getattr(dut, f'clk{idx}'))
        getattr(dut, f'csr_write{idx}').value = 0
        getattr(dut, f'csr_addr{idx}').value = BinaryValue('x' * addr_len)
        getattr(dut, f'csr_wdata{idx}').value = BinaryValue('x' * wdata_len)
        getattr(dut, f'cs{idx}').value = 0


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
            await csr_write(dut, idx, REG_TX, val, True)
        else:
            await csr_write(dut, idx, REG_TX, val, False)

async def read_rx(dut, idx, len_):
    ret = b''
    if len_ == 0:
        return ret
    await csr_read(dut, idx, REG_RX, True) # skip 1 clk ram output delay
    blk_cnt = int((len_+3)/4)
    left = len_%4
    for i in range(blk_cnt):
        if i < blk_cnt - 1:
            val = await csr_read(dut, idx, REG_RX, True)
        else:
            val = await csr_read(dut, idx, REG_RX, False, True)
            if left != 0:
                start = (4 - left) * 8
                val = val[start : 31]
        ret += struct.pack('<I', int(val))
    return ret[0: len_]

async def read_int_flag(dut, idx):
    val = await csr_read(dut, idx, REG_INT_FLAG)
    val = val[24 : 31]
    return int(val)

async def read_rx_len(dut, idx):
    val = await csr_read(dut, idx, REG_INT_FLAG)
    val = val[16 : 23]
    return int(val)

async def read_int_flag2(dut, idx):
    val = await csr_read(dut, idx, REG_INT_FLAG)
    return val[24 : 31], val[16 : 23]


async def exit_err():
    await Timer(100, units='ns')
    exit(-1)

async def exit_ok():
    await Timer(10, units='us')
    with open('.exit_ok', 'w') as f:
        f.write('ok')

