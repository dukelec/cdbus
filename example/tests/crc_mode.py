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

# crc mode test shared by spi, qspi and i2c, io is the interface:
#   io.cmd(address, is_write)       first byte of a transfer (i2c: after the device address)
#   io.write(datas)                 one transfer, all bytes from the host; i2c returns the last ack
#   io.read(address, len)           read without crc
#   io.crc_read(address, len)       returns write status, data and crc of a crc mode read
#   io.crc_head                     bytes before cmd covered by the crc (i2c: device address)
#   io.crc_mid(status)              same between n-1 and the data of a read: status (i2c: device address first)
#   io.rx_pending                   signal handle
#   io.sdo_early                    signal handle, None for i2c

from common import *

class CrcMode:
    def __init__(self, dut, io):
        self.dut = dut
        self.io = io
        self.status = 0xf0 # write status of the last read

    async def error(self, msg):
        self.dut._log.error(msg)
        await exit_err()

    # the status toggles between 0xf0 and 0x0f at each accepted write
    async def crc_read(self, address, len = 1):
        io = self.io
        status, datas, crc = await io.crc_read(address, len)
        if spi_crc16(io.crc_head + [io.cmd(address, False), len - 1] + io.crc_mid(status) + datas) != crc:
            await self.error(f'read crc error: {address:02x}')
        if status != 0xf0 and status != 0x0f:
            await self.error(f'wrong write status: {status:02x}')
        toggled = status != self.status
        self.status = status
        return datas, toggled

    def crc_frame(self, address, datas, crc_xor = 0):
        frame = [self.io.cmd(address, True), len(datas) - 1] + datas
        crc = spi_crc16(self.io.crc_head + frame) ^ crc_xor
        return frame + [crc >> 8, crc & 0xff]

    # crc_xor: break the crc; cut: drop the last bytes of the transfer
    async def crc_write(self, address, datas, accepted = True, crc_xor = 0, cut = 0):
        frame = self.crc_frame(address, datas, crc_xor)
        ack = await self.io.write(frame[:len(frame)-cut])
        if ack != None and cut == 0 and ack != accepted:
            await self.error(f'write {address:02x}: ack of the crc: {ack}, expect: {accepted}')
        _, toggled = await self.crc_read(REG_VERSION)
        if toggled != accepted:
            await self.error(f'write {address:02x}: accepted: {toggled}, expect: {accepted}')

    # a disturbed command: the host means one address, the device gets another
    async def write_disturbed(self, meant, wire, datas):
        frame = self.crc_frame(meant, datas)
        frame[0] = self.io.cmd(wire, True)
        await self.io.write(frame)
        _, toggled = await self.crc_read(REG_VERSION)
        if toggled:
            await self.error(f'disturbed write {meant:02x} accepted')

    async def read_disturbed(self, meant, wire, len):
        io = self.io
        status, datas, crc = await io.crc_read(wire, len)
        if spi_crc16(io.crc_head + [io.cmd(meant, False), len - 1] + io.crc_mid(status) + datas) == crc:
            await self.error(f'disturbed read {meant:02x} not detected')

    async def expect_reg(self, address, expect, len = 1):
        datas, toggled = await self.crc_read(address, len)
        if datas != expect or toggled:
            await self.error(f'reg {address:02x}: {datas}, expect: {expect}, status toggled: {toggled}')

    async def expect_flag(self, mask, expect):
        datas, _ = await self.crc_read(REG_INT_FLAG_L, 3)
        if datas[0] & mask != expect:
            await self.error(f'int_flag: {datas[0]:02x}, mask: {mask:02x}, expect: {expect:02x}')
        return datas[1] # rx_len

    async def wait_rx(self):
        if not self.io.rx_pending.value:
            await RisingEdge(self.io.rx_pending)

    async def expect_rx(self, expect):
        await self.wait_rx()
        rx_len = await self.expect_flag(0x01, 0x01)
        await self.expect_reg(REG_DAT, expect, 3 + rx_len)

    async def run(self, clk_freq):
        dut = self.dut
        io = self.io
        clk_period = round(1000000000000 / clk_freq)

        await io.write([io.cmd(REG_PIN_CFG, True), 0b00000001]) # push-pull
        await io.write([io.cmd(REG_DIV_LS_H, True), 0])
        await io.write([io.cmd(REG_DIV_LS_L, True), 39])
        await io.write([io.cmd(REG_DIV_HS_H, True), 0])
        await io.write([io.cmd(REG_DIV_HS_L, True), 3])
        await io.write([io.cmd(REG_FILTER, True), 0x00])

        await io.write([io.cmd(REG_INTF_CFG, True), BIT_INTF_CRC_MODE])
        await self.expect_reg(REG_INTF_CFG, [BIT_INTF_CRC_MODE])
        await self.expect_reg(REG_VERSION, [DFT_VERSION])
        await self.expect_reg(REG_SETTING, [BIT_SETTING_MODE_ARBIT])

        # a register takes the byte after the crc check only
        await self.crc_write(REG_FILTER_M0, [0x12])
        await self.expect_reg(REG_FILTER_M0, [0x12])
        await self.crc_write(REG_FILTER_M0, [0x34], False, crc_xor=0x0001)
        await self.crc_write(REG_FILTER_M0, [0x34], False, crc_xor=0x8000)
        await self.crc_write(REG_FILTER_M0, [0x34], False, cut=1)
        await self.crc_write(REG_FILTER_M0, [0x34, 0x56], False) # one byte only
        await self.expect_reg(REG_FILTER_M0, [0x12])
        await io.write([io.cmd(REG_FILTER_M0, True), 0x34]) # without crc
        await self.expect_reg(REG_FILTER_M0, [0x12])

        # the status read between the high and the low byte does not drop the high byte
        await self.crc_write(REG_TX_PERMIT_LEN_H, [0x01])
        await self.crc_write(REG_TX_PERMIT_LEN_L, [0x23])
        await self.expect_reg(REG_TX_PERMIT_LEN_L, [0x23])
        await self.expect_reg(REG_TX_PERMIT_LEN_H, [0x01])
        await self.crc_write(REG_TX_PERMIT_LEN_L, [0x14])
        await self.expect_reg(REG_TX_PERMIT_LEN_H, [0x00])

        # the page is not released by a read: read again, after DAT_HOLD set the position first
        tx_pkt = [0x01, 0x00, 0x01, 0xcd]
        await self.crc_write(REG_DAT, tx_pkt)
        await self.expect_rx(tx_pkt)
        await self.expect_reg(REG_DAT, tx_pkt, 4)
        await self.expect_reg(REG_DAT_HOLD, tx_pkt[0:2], 2)
        await self.expect_reg(REG_DAT_HOLD, tx_pkt[2:], 2) # position kept
        await self.crc_write(REG_RX_ADDR, [0])
        await self.expect_reg(REG_DAT_HOLD, tx_pkt[0:3], 3)
        await self.crc_write(REG_RX_ADDR, [2])
        await self.expect_reg(REG_DAT, tx_pkt[2:], 2)
        await self.expect_reg(REG_DAT, tx_pkt, 4)
        await self.expect_flag(0x01, 0x01)
        await self.crc_write(REG_CTRL, [0x10], False, crc_xor=0x0100)
        await self.expect_flag(0x01, 0x01)
        await self.crc_write(REG_CTRL, [0x10]) # release
        await Timer(clk_period * 10)
        await self.expect_flag(0x31, 0x30)

        # event flags are cleared by writing 1 to INT_FLAG_L
        await Timer(15000000)
        await send_frame(dut, b'\x05\x00\x01\xcd\x00', clk_freq, 39, 3) # incomplete: data_len is 1
        await Timer(15000000)
        await self.expect_flag(0x09, 0x08)
        await self.expect_flag(0x09, 0x08)
        await self.crc_write(REG_INT_FLAG_L, [0x08], False, crc_xor=0x0010)
        await self.expect_flag(0x09, 0x08)
        await self.crc_write(REG_INT_FLAG_L, [0x08])
        await self.expect_flag(0x09, 0x00)

        # a rejected frame is not sent, write it again
        await self.crc_write(REG_DAT, [0x01, 0x00, 0x01, 0xee], False, crc_xor=0x0002)
        await Timer(40000000)
        await self.expect_flag(0x31, 0x30)
        tx_pkt = [0x01, 0x00, 0x02, 0xaa, 0xbb]
        await self.crc_write(REG_DAT, tx_pkt)
        await self.expect_rx(tx_pkt)
        await self.crc_write(REG_CTRL, [0x10])

        # a page written in parts: clear it after a rejected part and start again
        tx_pkt = [0x01, 0x00, 0x06, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15]
        await self.crc_write(REG_DAT_HOLD, tx_pkt[0:2])
        await self.crc_write(REG_DAT_HOLD, [0xee, 0xee, 0xee], False, crc_xor=0x4000)
        await self.crc_write(REG_CTRL, [0x04])
        await self.crc_write(REG_DAT_HOLD, tx_pkt[0:5])
        await self.crc_write(REG_DAT, [0xdd, 0xdd, 0xdd, 0xdd], False, cut=2)
        await Timer(40000000)
        await self.expect_flag(0x31, 0x30) # not submitted
        await self.crc_write(REG_CTRL, [0x04])
        await self.crc_write(REG_DAT_HOLD, tx_pkt[0:5])
        await self.crc_write(REG_DAT, tx_pkt[5:])
        await self.expect_rx(tx_pkt)
        await self.crc_write(REG_CTRL, [0x10])
        await Timer(clk_period * 10)
        await self.expect_flag(0x31, 0x30)

        # after a failure: write RX_ADDR before reading the RX page again, restart the TX page
        tx_pkt = [0x01, 0x00, 0x04, 0xa0, 0xa1, 0xa2, 0xa3]
        await self.crc_write(REG_DAT, tx_pkt)
        await self.wait_rx()
        await self.read_disturbed(REG_DAT, REG_DAT_HOLD, 4) # moves the read position
        await self.crc_write(REG_RX_ADDR, [0])
        await self.expect_reg(REG_DAT, tx_pkt[0:4], 4)
        await self.write_disturbed(REG_CTRL, REG_DAT_HOLD, [0x10]) # 0x10 into the TX page
        await self.crc_write(REG_CTRL, [0x10])
        await self.crc_write(REG_CTRL, [0x04])
        tx_pkt = [0x01, 0x00, 0x02, 0xb0, 0xb1]
        await self.crc_write(REG_DAT, tx_pkt)
        await self.expect_rx(tx_pkt)
        await self.crc_write(REG_CTRL, [0x10])

        # no free TX page: disturbed and rejected writes do not reach the frames waiting to be sent
        pkts = [[0x01, 0x00, 0x02, 0xc0 + i, 0xd0 + i] for i in range(3)]
        dut.bus_a.value = 0 # bus busy
        await Timer(20000000)
        await self.crc_write(REG_DAT, pkts[0])
        await self.crc_write(REG_DAT, pkts[1])
        await self.expect_flag(0x10, 0x00)
        await self.write_disturbed(REG_CTRL, REG_DAT_HOLD, [0x10])
        dut.bus_a.value = Logic('z')
        await self.crc_write(REG_DAT_HOLD, [0xee] * 200, False, crc_xor=0x0001) # a page gets free meanwhile
        for pkt in pkts[0:2]:
            await self.expect_rx(pkt)
            await self.crc_write(REG_CTRL, [0x10])
        await self.crc_write(REG_INT_FLAG_L, [0xce]) # a break if the bus was held long enough
        await self.crc_write(REG_CTRL, [0x04])
        await self.crc_write(REG_DAT, pkts[2])
        await self.expect_rx(pkts[2])
        await self.crc_write(REG_CTRL, [0x10])

        # sdo half a clock earlier for spi and qspi
        await self.crc_write(REG_INTF_CFG, [BIT_INTF_SDO_EARLY | BIT_INTF_CRC_MODE])
        await self.expect_reg(REG_INTF_CFG, [BIT_INTF_SDO_EARLY | BIT_INTF_CRC_MODE])
        if io.sdo_early != None and not io.sdo_early.value:
            await self.error('sdo_early not set')

        # a full page in one transfer
        tx_pkt = [0x01, 0x00, 253] + [(i * 7 + 3) & 0xff for i in range(253)]
        await self.crc_write(REG_DAT, tx_pkt)
        await self.expect_rx(tx_pkt)
        await self.crc_write(REG_CTRL, [0x10])

        # back to the transfers without crc
        await io.write(self.crc_frame(REG_INTF_CFG, [0]))
        value = await io.read(REG_INTF_CFG, 2) + await io.read(REG_SETTING, 2)
        if value != [0, 0, BIT_SETTING_MODE_ARBIT, BIT_SETTING_MODE_ARBIT]:
            await self.error(f'wrong intf_cfg or setting: {value}')
        tx_pkt = [0x01, 0x00, 0x02, 0x55, 0x66]
        await io.write([io.cmd(REG_DAT, True)] + tx_pkt)
        await self.wait_rx()
        value = await io.read(REG_DAT, 5) # auto release
        await Timer(clk_period * 10)
        int_flag = (await io.read(REG_INT_FLAG_L, 1))[0]
        if value != tx_pkt or int_flag != 0x30:
            await self.error(f'wrong frame or int_flag: {value}, {int_flag:02x}')

        # without crc as well: a read between the high and the low byte
        await io.write([io.cmd(REG_MAX_IDLE_LEN_H, True), 0x02])
        await io.read(REG_VERSION, 1)
        await io.write([io.cmd(REG_MAX_IDLE_LEN_L, True), 0x34])
        value = await io.read(REG_MAX_IDLE_LEN_L, 1) + await io.read(REG_MAX_IDLE_LEN_H, 1)
        if value != [0x34, 0x02]:
            await self.error(f'wrong max_idle_len: {value}')
