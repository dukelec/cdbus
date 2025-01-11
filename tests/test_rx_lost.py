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
import math, random
from cocotb.binary import BinaryValue
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly, Timer
from cocotb.clock import Clock
from common import *

@cocotb.test(timeout_time=4500, timeout_unit='us')
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
    
    val = await csr_read(dut, 0, REG_SETTING)
    dut._log.info(f'idx0 REG_SETTING: 0x{int(val):02x}')

    await csr_write(dut, 0, REG_SETTING, BinaryValue('00010001'))
    await csr_write(dut, 1, REG_SETTING, BinaryValue('00010001'))
    await csr_write(dut, 0, REG_INT_MASK_L, BinaryValue('11101111')) # TX page released
    await csr_write(dut, 1, REG_INT_MASK_L, BinaryValue('11001111'))
    
    await set_div(dut, 0, 39, 2) # 1Mbps, 13.333Mbps
    await set_div(dut, 1, 39, 2)
    
    await csr_write(dut, 0, REG_FILTER, 0x01) # set local filter to 0x01
    await csr_write(dut, 1, REG_FILTER, 0x02) # set local filter to 0x02
    
    
    # send multiple packages at first:
    
    user_size = [32, 28, 27, 253, 1, 31, 128, 200, 12, 7, 0, 29, 88, 253, 252, 13, 55, 60, 34, 200, 149]
    ram_used = [] # 37, 33, 32, min(258,256)=256, ...
    frag_amount = []
    frag_amounts = 0
    
    for i in range(len(user_size)):
        ram_u = min(user_size[i] + 5, 256)
        ram_used.append(ram_u)
        amount = math.ceil(ram_u / 32)
        frag_amount.append(amount)
        frag_amounts += amount
    dut._log.info(f'user size table: {user_size}')
    dut._log.info(f'sram size used:  {ram_used}')
    dut._log.info(f'frag amount   :  {frag_amount}, total: {frag_amounts}')
    
    tx_pkt_strs = []
    
    for i in range(len(user_size)):
        payload = b''
        for x in range(user_size[i]):
            #payload += bytes([random.randint(0,255)])
            payload += bytes([x])
        dut._log.info(f'payload len: {len(payload)}')
        tx_pkt = b'\x01\x02' + bytes([len(payload)]) + payload
        tx_pkt_strs.append(tx_pkt.hex())
        
        dut._log.info(f'send frame: {i}')
        await write_tx(dut, 0, tx_pkt) # node 0x01 send to 0x02
        #await csr_write(dut, 0, REG_CTRL, BIT_TX_START)
        await RisingEdge(dut.irq0)
        
        dirty = dut.cdbus_m1.cd_rx_ram_m.dirty.value;
        wr_sel = dut.cdbus_m1.cd_rx_ram_m.wr_sel.value.integer;
        rd_sel = dut.cdbus_m1.cd_rx_ram_m.rd_sel.value.integer;
        rx_pend_len = dut.cdbus_m1.cd_csr_m.rx_pend_len.value.integer;
        dut._log.info(f'dirty flag: {dirty}, {dirty.integer:016x}, w:{wr_sel} r:{rd_sel}, pend_len: {rx_pend_len}')
    
    
    await Timer(10, units='us')
    dirty = dut.cdbus_m1.cd_rx_ram_m.dirty.value;
    wr_sel = dut.cdbus_m1.cd_rx_ram_m.wr_sel.value.integer;
    rd_sel = dut.cdbus_m1.cd_rx_ram_m.rd_sel.value.integer;
    rx_pend_len = dut.cdbus_m1.cd_csr_m.rx_pend_len.value.integer;
    dut._log.info(f'dirty flag: {dirty}, {dirty.integer:016x}, w:{wr_sel} r:{rd_sel}, pend_len: {rx_pend_len} (before first read)')
    if dirty.integer != 0x04b01012f0216035:
        dut._log.error(f'wrong dirty value')
        await exit_err()
    
    
    # read first package from buffer:
    
    val = await read_int_flag(dut, 1)
    rx_len = await read_rx_len(dut, 1)
    dut._log.info(f'{0}: REG_INT_FLAG: 0x{int(val):02x}, rx len: {int(rx_len)}')
    if val & BIT_FLAG_RX_LOST:
        dut._log.info(f'lost detected')
    else:
        dut._log.error(f'rx lost not detect')
        await exit_err()
    
    if not (val & BIT_FLAG_RX_PENDING):
        dut._log.error(f'no rx for read, break')
        await exit_err()
    str_ = (await read_rx(dut, 1, user_size[0] + 3)).hex()
    dut._log.info(f'idx1: sent:     {tx_pkt_strs[0]}')
    dut._log.info(f'idx1: received: {str_}')
    if str_ != tx_pkt_strs[0]:
        dut._log.error(f'idx1: receive mismatch')
        await exit_err()
    #await csr_write(dut, 1, REG_CTRL, BIT_RX_CLR_PENDING)
    
    await Timer(1, units='us')
    dirty = dut.cdbus_m1.cd_rx_ram_m.dirty.value;
    wr_sel = dut.cdbus_m1.cd_rx_ram_m.wr_sel.value.integer;
    rd_sel = dut.cdbus_m1.cd_rx_ram_m.rd_sel.value.integer;
    rx_pend_len = dut.cdbus_m1.cd_csr_m.rx_pend_len.value.integer;
    dut._log.info(f'dirty flag: {dirty}, {dirty.integer:016x}, w:{wr_sel} r:{rd_sel}, pend_len: {rx_pend_len} (after first read)')
    
    
    # send one more package:
    
    payload = b''
    last_send_size = 6*32-5
    for x in range(last_send_size):
        #payload += bytes([random.randint(0,255)])
        payload += bytes([x])
    dut._log.info(f'payload len: {len(payload)}')
    tx_pkt = b'\x01\x02' + bytes([len(payload)]) + payload
    tx_pkt_strs.append(tx_pkt.hex())
    
    dut._log.info(f'send frame: ')
    await write_tx(dut, 0, tx_pkt) # node 0x01 send to 0x02
    #await csr_write(dut, 0, REG_CTRL, BIT_TX_START)
    await RisingEdge(dut.irq0)
    
    dirty = dut.cdbus_m1.cd_rx_ram_m.dirty.value;
    wr_sel = dut.cdbus_m1.cd_rx_ram_m.wr_sel.value.integer;
    rd_sel = dut.cdbus_m1.cd_rx_ram_m.rd_sel.value.integer;
    rx_pend_len = dut.cdbus_m1.cd_csr_m.rx_pend_len.value.integer;
    dut._log.info(f'dirty flag: {dirty}, {dirty.integer:016x}, w:{wr_sel} r:{rd_sel}, pend_len: {rx_pend_len}')
    
    
    # read all packages except last one:
    
    for i in range(1, len(user_size)-2):
        val = await read_int_flag(dut, 1)
        rx_len = await read_rx_len(dut, 1)
        dut._log.info(f'{i}: REG_INT_FLAG: 0x{int(val):02x}, rx len: {int(rx_len)}')
        if val & BIT_FLAG_RX_LOST:
            dut._log.error(f'lost detected')
            await exit_err()
        if not (val & BIT_FLAG_RX_PENDING):
            dut._log.error(f'no rx for read, break')
            await exit_err()
        str_ = (await read_rx(dut, 1, user_size[i] + 3)).hex()
        dut._log.info(f'idx1: sent:     {tx_pkt_strs[i]}')
        dut._log.info(f'idx1: received: {str_}')
        if str_ != tx_pkt_strs[i]:
            dut._log.error(f'idx1: receive mismatch')
            await exit_err()
        #await csr_write(dut, 1, REG_CTRL, BIT_RX_CLR_PENDING)
        
        await Timer(1, units='us')
        dirty = dut.cdbus_m1.cd_rx_ram_m.dirty.value;
        wr_sel = dut.cdbus_m1.cd_rx_ram_m.wr_sel.value.integer;
        rd_sel = dut.cdbus_m1.cd_rx_ram_m.rd_sel.value.integer;
        rx_pend_len = dut.cdbus_m1.cd_csr_m.rx_pend_len.value.integer;
        dut._log.info(f'dirty flag: {dirty}, {dirty.integer:016x}, w:{wr_sel} r:{rd_sel}, pend_len: {rx_pend_len}')

    
    # read last package:
    
    val = await read_int_flag(dut, 1)
    rx_len = await read_rx_len(dut, 1)
    dut._log.info(f'{0}: REG_INT_FLAG: 0x{int(val):02x}, rx len: {int(rx_len)}')
    if val & BIT_FLAG_RX_LOST:
        dut._log.info(f'lost detected')
    if not (val & BIT_FLAG_RX_PENDING):
        dut._log.error(f'no rx for read, break')
        await exit_err()
    str_ = (await read_rx(dut, 1, last_send_size + 3)).hex()
    dut._log.info(f'idx1: sent:     {tx_pkt_strs[-1]}')
    dut._log.info(f'idx1: received: {str_}')
    if str_ != tx_pkt_strs[-1]:
        dut._log.error(f'idx1: receive mismatch')
        await exit_err()
    #await csr_write(dut, 1, REG_CTRL, BIT_RX_CLR_PENDING)
    
    await Timer(1, units='us')
    dirty = dut.cdbus_m1.cd_rx_ram_m.dirty.value;
    wr_sel = dut.cdbus_m1.cd_rx_ram_m.wr_sel.value.integer;
    rd_sel = dut.cdbus_m1.cd_rx_ram_m.rd_sel.value.integer;
    rx_pend_len = dut.cdbus_m1.cd_csr_m.rx_pend_len.value.integer;
    dut._log.info(f'dirty flag: {dirty}, {dirty.integer:016x}, w:{wr_sel} r:{rd_sel}, pend_len: {rx_pend_len} (after last read)')
    
    
    # send one more package at last:
    
    await write_tx(dut, 0, b'\x01\x02\x01\xcd') # node 0x01 send to 0x02
    #await csr_write(dut, 0, REG_CTRL, BIT_TX_START)
    
    # read back:
    
    await RisingEdge(dut.irq1)
    val = await read_int_flag(dut, 1)
    rx_len = await read_rx_len(dut, 1)
    dut._log.info(f'REG_INT_FLAG: 0x{int(val):02x}, rx len: {int(rx_len)}')
    
    str_ = (await read_rx(dut, 1, 6)).hex() # read 6 bytes (include crc)
    dut._log.info(f'idx1: received: {str_}')
    if str_ != '010201cd601d':
        dut._log.error(f'idx1: receive mismatch')
        await exit_err()
    
    #await csr_write(dut, 1, REG_CTRL, BIT_RX_CLR_PENDING)
    await FallingEdge(dut.irq1)
    
    await Timer(1, units='us')
    dirty = dut.cdbus_m1.cd_rx_ram_m.dirty.value;
    wr_sel = dut.cdbus_m1.cd_rx_ram_m.wr_sel.value.integer;
    rd_sel = dut.cdbus_m1.cd_rx_ram_m.rd_sel.value.integer;
    dut._log.info(f'dirty flag: {dirty}, {dirty.integer:016x}, w:{wr_sel} r:{rd_sel}, (end)')
    
    if dirty.integer != 0:
        dut._log.error(f'wrong dirty value')
        await exit_err()
    
    dut._log.info('test_cdbus done.')
    await exit_ok()

