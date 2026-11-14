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

# Transparent mode: the crc is the host's, rx pages hold up to 255 bytes,
# a shorter page (an empty one too) ends the frame.

from common import *
from common import _send_bytes

SYS_CLK = 40000000
DIV = 2 # 13.3Mbps, the tightest timing
BIT_NS = (DIV + 1) * 25

# raw tx page: [reserved, reserved, data_len, data...], data_len + 2 bytes are sent,
# the bytes beyond the page wrap around to the start
async def raw_tx(dut, idx, data):
    await write_tx(dut, idx, bytes([0, 0, len(data) - 2]) + data)

async def wait_rx(dut, idx):
    for _ in range(1000):
        await Timer(1, unit='us')
        val = int(await read_int_flag(dut, idx))
        if val & BIT_FLAG_RX_PENDING:
            return val
    dut._log.error(f'idx{idx}: no rx page')
    await exit_err()

async def read_page(dut, idx):
    val = await wait_rx(dut, idx)
    if val & BIT_FLAG_RX_ERROR:
        dut._log.error(f'idx{idx}: rx error flagged')
        await exit_err()
    n = (int(await read_rx_len(dut, idx)) + 1) & 0xff # 0xff: empty page
    if n:
        return await read_rx(dut, idx, n)
    await csr_write(dut, idx, REG_CTRL, BIT_RX_CLR_PENDING)
    return b''

# read the pages of one frame, the last one is shorter than 255 bytes
async def raw_rx_check(dut, idx, expect, sizes):
    got_sizes, got = [], b''
    while not got_sizes or got_sizes[-1] == 255:
        page = await read_page(dut, idx)
        got_sizes.append(len(page))
        got += page
    dut._log.info(f'idx{idx}: pages {got_sizes}')
    if got_sizes != sizes or got != expect:
        dut._log.error(f'idx{idx}: expect pages {sizes}, receive mismatch')
        await exit_err()

async def check_no_rx(dut, idx, what):
    await Timer(20 * BIT_NS, unit='ns')
    if int(await read_int_flag(dut, idx)) & BIT_FLAG_RX_PENDING:
        dut._log.error(f'idx{idx}: {what}')
        await exit_err()


@cocotb.test(timeout_time=40000, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')

    clk_period = 1000000000000 / SYS_CLK
    cocotb.start_soon(Clock(dut.clk0, clk_period).start())
    cocotb.start_soon(Clock(dut.clk1, clk_period).start())
    await reset(dut, 0)
    await reset(dut, 1)
    await check_version(dut, 0)
    await check_version(dut, 1)

    for idx in [0, 1]:
        await csr_write(dut, idx, REG_SETTING, BIT_SETTING_RAW | BIT_SETTING_MODE_HALF)
        await csr_write(dut, idx, REG_PIN_CFG, BIT_PIN_CFG_TX_PUSH_PULL)
        await set_div(dut, idx, DIV, DIV)

    # modbus style frame, the crc comes from the host; own echo is dropped
    data = b'\x01\x03\x00\x00\x00\x0a'
    data += modbus_crc(data)
    await raw_tx(dut, 0, data)
    await raw_rx_check(dut, 1, data, [8])
    await check_no_rx(dut, 0, 'echo not dropped')

    # a full page is followed by an empty one
    data = bytes(range(255))
    await raw_tx(dut, 0, data)
    await raw_rx_check(dut, 1, data, [255, 0])
    await check_no_rx(dut, 0, 'echo not dropped')

    # a page queued before the previous one is sent follows it in the same frame
    data = bytes([i * 3 & 0xff for i in range(200)]) + bytes(range(100))
    await raw_tx(dut, 0, data[:200])
    await raw_tx(dut, 0, data[200:])
    await raw_rx_check(dut, 1, data, [255, 45])
    await check_no_rx(dut, 0, 'echo not dropped')

    # a page queued after the previous one is sent starts a new frame
    await raw_tx(dut, 0, b'\x11\x22\x33')
    while int(await read_int_flag(dut, 0)) & BIT_FLAG_TX_BUF_CLEAN: # the first read can be older than the submit
        await Timer(1, unit='us')
    while not int(await read_int_flag(dut, 0)) & BIT_FLAG_TX_BUF_CLEAN:
        await Timer(1, unit='us')
    await raw_tx(dut, 0, b'\x44\x55')
    await raw_rx_check(dut, 1, b'\x11\x22\x33', [3])
    await raw_rx_check(dut, 1, b'\x44\x55', [2])
    await check_no_rx(dut, 0, 'echo not dropped') # its last byte arrives after tx is done

    # frames from a plain uart on the bus, both nodes receive; no crc check
    for n, sizes in [(600, [255, 255, 90]), (510, [255, 255, 0]), (256, [255, 1]), (5, [5])]:
        data = bytes([i * 7 & 0xff for i in range(n)])
        await _send_bytes(dut, data, SYS_CLK, DIV, False)
        await raw_rx_check(dut, 0, data, sizes)
        await raw_rx_check(dut, 1, data, sizes)

    # a single byte is noise
    await _send_bytes(dut, b'\x5a', SYS_CLK, DIV, False)
    await check_no_rx(dut, 0, 'single byte not dropped')
    await check_no_rx(dut, 1, 'single byte not dropped')

    # 8 full pages fill the rx ram: the empty page after them is lost, the first page stays intact
    data = bytes([i * 5 & 0xff for i in range(255 * 8)])
    await _send_bytes(dut, data, SYS_CLK, DIV, False)
    await Timer(20 * BIT_NS, unit='ns')
    for idx in [0, 1]:
        if not int(await read_int_flag(dut, idx)) & BIT_FLAG_RX_LOST:
            dut._log.error(f'idx{idx}: lost empty page not flagged')
            await exit_err()
        for i in range(8):
            if await read_page(dut, idx) != data[i * 255 : (i + 1) * 255]:
                dut._log.error(f'idx{idx}: page {i} mismatch')
                await exit_err()
        await check_no_rx(dut, idx, 'lost empty page received')

    # loopback: own echo is kept
    await csr_write(dut, 0, REG_SETTING, BIT_SETTING_RAW | BIT_SETTING_RAW_LOOPBACK)
    data = bytes(range(255)) + b'\xcd\xcd'
    await raw_tx(dut, 0, data[:255])
    await raw_tx(dut, 0, data[255:])
    await raw_rx_check(dut, 0, data, [255, 2])
    await raw_rx_check(dut, 1, data, [255, 2])

    dut._log.info('test_cdbus done.')
    await exit_ok()
