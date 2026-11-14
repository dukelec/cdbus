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

# RX of a frame that starts right when the bus becomes idle. Frames are driven on bus_a from outside,
# node1 (0x02) receives. The second frame starts one clock later in every round, across the clock on
# which the idle wait after the first one ends: once node1 has seen the bus idle, even for a single
# clock, the frame must be received.

from common import *

CLK_PS = 25000 # 40MHz

def frame_of(payload):
    return payload + modbus_crc(payload)

async def drive(dut, frame, clocks, skew):
    for byte in frame:
        for bit in [0] + [(byte >> i) & 1 for i in range(8)] + [1]:
            dut.bus_a.value = 0 if bit == 0 else Logic('z')
            await Timer(round(clocks * CLK_PS * skew), unit='ps')
    dut.bus_a.value = Logic('z')


@cocotb.test(timeout_time=6000, timeout_unit='us')
async def test_cdbus(dut):
    dut._log.info('test_cdbus start.')
    for i in range(3):
        cocotb.start_soon(Clock(getattr(dut, f'clk{i}'), CLK_PS).start())
    for i in range(3):
        await reset(dut, i)
    await csr_write(dut, 1, REG_FILTER, 0x02)

    frame_a = frame_of(b'\x01\x02\x01\x5a')
    frame_b = frame_of(b'\x03\x02\x01\xa5')
    bus_idle = dut.cdbus_m1.bus_idle

    # frame_a, then frame_b gap clocks later (None: frame_a only);
    # returns the clocks until bus idle (frame_a only), whether bus idle was seen before frame_b, the frames received
    async def round_(clocks, skew, gap):
        await Timer(15 * clocks * CLK_PS, unit='ps')
        await RisingEdge(dut.clk1)
        await Timer(7, unit='ns') # keep away from the clock edge
        await drive(dut, frame_a, clocks, skew)
        n = 0
        idle_seen = False
        for _ in range(12 * clocks if gap is None else gap + 8):
            if gap is not None and n == gap:
                task = cocotb.start_soon(drive(dut, frame_b, clocks, skew))
            await RisingEdge(dut.clk1)
            n += 1
            if bus_idle.value == 1:
                if gap is None:
                    break
                idle_seen = True
        if gap is not None:
            await task
        await Timer(15 * clocks * CLK_PS, unit='ps')
        got = []
        for _ in range(2):
            flag = int(await read_int_flag(dut, 1))
            if flag & BIT_FLAG_RX_ERROR:
                got.append(b'error')
            if flag & BIT_FLAG_RX_PENDING:
                got.append(await read_rx(dut, 1, len(frame_a)))
            await Timer(500, unit='ns') # the flag snapshot of the next read must be fresh
        return n, idle_seen, got

    for clocks in (3, 4, 5, 6):
        await set_div(dut, 1, clocks - 1, clocks - 1)
        for skew in (0.98, 1, 1.02):
            n_idle, _, got = await round_(clocks, skew, None)
            if got != [frame_a]:
                dut._log.error(f'{clocks} clk/bit, skew {skew}: first frame not received')
                await exit_err()
            seen = []
            for gap in range(n_idle - 7, n_idle + 2):
                _, idle_seen, got = await round_(clocks, skew, gap)
                seen.append(idle_seen)
                dut._log.info(f'{clocks} clk/bit, skew {skew}, gap {gap} clocks: bus idle seen: {idle_seen}, '
                              f'received: {[f.hex() if f != b"error" else "error" for f in got]}')
                if got != ([frame_a, frame_b] if idle_seen else [frame_a]):
                    dut._log.error('second frame: received if and only if the bus was idle before it')
                    await exit_err()
            if seen[0] or not seen[-1]:
                dut._log.error('the sweep does not cross the end of the idle wait')
                await exit_err()

    dut._log.info('test_cdbus done.')
    await exit_ok()
