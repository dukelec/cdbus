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
from common import _send_bytes

# raw tx page: [reserved, reserved, data_len, data...], crc appended by hardware
async def raw_tx(dut, idx, data, user_crc=False):
    len_ = len(data) - 2 if user_crc else len(data)
    await write_tx(dut, idx, bytes([0, 0, len_]) + data)

async def wait_rx(dut, idx):
    while True:
        await Timer(1, unit='us') # let the previous transfer settle
        try:
            val = int(await read_int_flag(dut, idx))
        except ValueError: # bit3 is undefined before the page arrives with save broken frame
            continue
        if val & BIT_FLAG_RX_PENDING:
            return val

# expect one rx page (including crc), flag bit3 means crc error
async def raw_rx_check(dut, idx, expect, crc_err=False):
    val = await wait_rx(dut, idx)
    rx_len = int(await read_rx_len(dut, idx)) + 1 # len - 1
    dut._log.info(f'idx{idx}: int_flag: 0x{int(val):02x}, rx_len: {rx_len}')
    if rx_len != len(expect) or bool(val & BIT_FLAG_RX_ERROR) != crc_err:
        dut._log.error(f'idx{idx}: wrong rx_len or flag')
        await exit_err()
    rx = await read_rx(dut, idx, rx_len)
    if rx != expect:
        dut._log.error(f'idx{idx}: receive mismatch: {rx.hex()}')
        await exit_err()


@cocotb.test(timeout_time=20000, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')

    sys_clk = 40000000
    clk_period = 1000000000000 / sys_clk

    cocotb.start_soon(Clock(dut.clk0, clk_period).start())
    cocotb.start_soon(Clock(dut.clk1, clk_period).start())
    await reset(dut, 0)
    await reset(dut, 1)
    await check_version(dut, 0)
    await check_version(dut, 1)

    val = await csr_read(dut, 0, REG_SETTING)
    dut._log.info(f'idx0 REG_SETTING: 0x{int(val):02x}')

    await csr_write(dut, 0, REG_SETTING, BIT_SETTING_RAW | BIT_SETTING_MODE_HALF)
    await csr_write(dut, 1, REG_SETTING, BIT_SETTING_RAW | BIT_SETTING_MODE_HALF)
    await csr_write(dut, 0, REG_PIN_CFG, BIT_PIN_CFG_TX_PUSH_PULL)
    await csr_write(dut, 1, REG_PIN_CFG, BIT_PIN_CFG_TX_PUSH_PULL)

    await set_div(dut, 0, 39, 39) # 1Mbps
    await set_div(dut, 1, 39, 39)

    # modbus style frame: crc appended and checked by hardware, own echo is dropped
    data = b'\x01\x03\x00\x00\x00\x0a'
    await raw_tx(dut, 0, data)
    await raw_rx_check(dut, 1, data + modbus_crc(data))
    val = int(await read_int_flag(dut, 0))
    if val & BIT_FLAG_RX_PENDING:
        dut._log.error('idx0: echo not dropped')
        await exit_err()

    # max tx payload: 253 bytes
    data = bytes(range(253))
    await raw_tx(dut, 0, data)
    await raw_rx_check(dut, 1, data + modbus_crc(data))

    # frames from a plain uart on the bus, both nodes receive; bad crc is flagged
    data = b'\x01\x03\x14\x00\x01\x00\x02'
    await _send_bytes(dut, data + modbus_crc(data), sys_clk, 39, False)
    await raw_rx_check(dut, 0, data + modbus_crc(data))
    await raw_rx_check(dut, 1, data + modbus_crc(data))
    await _send_bytes(dut, data + b'\x00\x00', sys_clk, 39, False) # bad crc: dropped, sticky flag
    await Timer(20, unit='us')
    for idx in [0, 1]:
        val = int(await read_int_flag(dut, idx))
        if (val & BIT_FLAG_RX_PENDING) or not (val & BIT_FLAG_RX_ERROR):
            dut._log.error(f'idx{idx}: bad crc frame not dropped or not flagged')
            await exit_err()
    await csr_write(dut, 1, REG_SETTING, BIT_SETTING_RAW | BIT_SETTING_NO_DROP) # save broken frame
    await _send_bytes(dut, data + b'\x00\x00', sys_clk, 39, False)
    await raw_rx_check(dut, 1, data + b'\x00\x00', True)

    # user crc: any content passes through, rx page up to 256 bytes
    await csr_write(dut, 0, REG_SETTING, BIT_SETTING_RAW | BIT_SETTING_USER_CRC)
    await csr_write(dut, 1, REG_SETTING, BIT_SETTING_RAW | BIT_SETTING_USER_CRC)
    data = b'\xff\x00\x80\x7f'
    await raw_tx(dut, 0, data, user_crc=True)
    await raw_rx_check(dut, 1, data)
    data = bytes(range(256))
    await _send_bytes(dut, data, sys_clk, 39, False)
    await raw_rx_check(dut, 0, data)
    await raw_rx_check(dut, 1, data)

    # loopback: own echo is kept
    await csr_write(dut, 0, REG_SETTING, BIT_SETTING_RAW | BIT_SETTING_USER_CRC | BIT_SETTING_RAW_LOOPBACK)
    data = b'\xcd\xcd'
    await raw_tx(dut, 0, data, user_crc=True)
    await raw_rx_check(dut, 0, data)
    await raw_rx_check(dut, 1, data)

    dut._log.info('test_cdbus done.')
    await exit_ok()
