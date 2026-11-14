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

# RX with noise. Frames and noise are driven on bus_a from outside, node1 (0x02) receives.
#  1. A low glitch shorter than half a bit is not a start bit and the receiver stays ready:
#     the frame after it is not lost. The same between two bytes of a frame.
#  2. A high spike inside a start bit, away from the sample point, does not move the sampling.
#  3. Single-clock glitches inside an inter-byte gap do not shorten the idle timeout.
#  4. Waiting for idle in the middle of a frame of 0xff bytes: no false bus idle.

from common import *

CLK_PS = 25000 # 40MHz

def frame_of(payload):
    return payload + modbus_crc(payload)

# one list of (level, clocks) per byte: [start, 8 data bits, stop], first byte at ls clocks per bit
def frame_segs(frame, ls, hs):
    segs = []
    for k, byte in enumerate(frame):
        n = ls if k == 0 else hs
        segs.append([(0, n)] + [((byte >> i) & 1, n) for i in range(8)] + [(1, n)])
    return segs

async def drive(dut, segs, skew=1):
    await RisingEdge(dut.clk1)
    await Timer(7, unit='ns') # keep away from the clock edge
    for level, n in sum(segs, []):
        dut.bus_a.value = 0 if level == 0 else Logic('z')
        await Timer(round(n * CLK_PS * skew), unit='ps')
    dut.bus_a.value = Logic('z')


@cocotb.test(timeout_time=3000, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')
    for i in range(3):
        cocotb.start_soon(Clock(getattr(dut, f'clk{i}'), CLK_PS).start())
    for i in range(3):
        await reset(dut, i)
    await csr_write(dut, 1, REG_FILTER, 0x02)

    frame = frame_of(b'\x01\x02\x03\xcd\xab\x55')

    async def check(what, segs, skew=1):
        await drive(dut, segs, skew)
        await Timer(40, unit='us') # bus idle
        flag = int(await read_int_flag(dut, 1))
        rx = await read_rx(dut, 1, len(frame)) if flag & BIT_FLAG_RX_PENDING else b''
        dut._log.info(f'{what}: int_flag: 0x{flag:02x}, received: {rx.hex()}')
        if rx != frame or flag & BIT_FLAG_RX_ERROR:
            dut._log.error(f'{what}: frame not received')
            await exit_err()

    ls, hs = 40, 10
    await set_div(dut, 1, ls - 1, hs - 1)
    await Timer(40, unit='us')

    await check('glitch 3 bits before the frame', [[(0, 8), (1, 3 * ls - 8)]] + frame_segs(frame, ls, hs))

    segs = frame_segs(frame, ls, hs)
    segs[0][9:] = [(1, 24), (0, 2), (1, 14)]
    await check('glitch in the stop bit', segs)

    segs = frame_segs(frame, ls, hs)
    segs[0] += [(1, 2 * ls), (0, 3), (1, 3 * ls - 3)]
    await check('glitch in a 5-bit gap', segs)

    segs = frame_segs(frame, ls, hs)
    segs[3][:1] = [(0, 2), (1, 2), (0, 6)]
    await check('spike in a start bit, sender 2% fast', segs, 0.98)

    ls, hs = 40, 3
    await set_div(dut, 1, ls - 1, hs - 1)
    segs = frame_segs(frame, ls, hs)
    segs[2] += [(1, 9), (0, 1)] * 12 + [(1, 5 * ls)] # 8-bit gap
    await check('single-clock glitches in an 8-bit gap', segs)

    ls = hs = 3
    await set_div(dut, 1, ls - 1, hs - 1)
    task = cocotb.start_soon(drive(dut, frame_segs(frame_of(b'\x01\x02\x3c' + b'\xff' * 60), ls, hs)))
    await Timer(8 * 10 * ls * CLK_PS, unit='ps')
    await csr_write(dut, 1, REG_CTRL, BIT_RX_RST) # wait for idle from here
    for _ in range(40 * 10 * ls):
        await RisingEdge(dut.clk1)
        if dut.cdbus_m1.bus_idle.value == 1:
            dut._log.error('bus idle in the middle of a frame')
            await exit_err()
    await task
    dut._log.info('no bus idle inside the 0xff frame')

    dut._log.info('test_cdbus done.')
    await exit_ok()
