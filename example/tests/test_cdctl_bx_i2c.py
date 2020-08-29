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
from cocotb.binary import BinaryValue
from cocotb.triggers import RisingEdge, ReadOnly, Timer
from cocotb.clock import Clock
from cocotb.result import ReturnValue, TestFailure

# pip3.6 install pycrc --user
from PyCRC.CRC16 import CRC16

def modbus_crc(data):
    return CRC16(modbus_flag = True).calculate(data).to_bytes(2, byteorder='little')


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
REG_INT_FLAG        = 0x10
REG_INT_MASK        = 0x11
REG_RX              = 0x14
REG_TX              = 0x15
REG_RX_CTRL         = 0x16
REG_TX_CTRL         = 0x17
REG_RX_ADDR         = 0x18
REG_RX_PAGE_FLAG    = 0x19
REG_FILTER1         = 0x1a
REG_FILTER2         = 0x1b

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


CLK_FREQ = 40000000
CLK_PERIOD = 1000000000000 / CLK_FREQ

I2C_FREQ = 2000000
I2C_PERIOD = 1000000000000 / I2C_FREQ


@cocotb.coroutine
def send_bytes(dut, bytes, factor, is_z = True):
    yield Timer(1000)
    factor += 1
    for byte in bytes:
        dut.bus_a = 0
        yield Timer(factor * CLK_PERIOD)
        for i in range(0,8):
            if byte & 0x01 == 0:
                dut.bus_a = 0
            else:
                dut.bus_a = BinaryValue("z") if is_z else 1
            yield Timer(factor * CLK_PERIOD)
            byte = byte >> 1
        dut.bus_a = BinaryValue("z") if is_z else 1
        yield Timer(factor * CLK_PERIOD)
        dut.bus_a = BinaryValue("z")

@cocotb.coroutine
def send_frame(dut, bytes, factor_l, factor_h):
    yield send_bytes(dut, bytes[0:1], factor_l)
    yield send_bytes(dut, bytes[1:], factor_h, False)
    yield send_bytes(dut, modbus_crc(bytes), factor_h, False)


@cocotb.coroutine
def i2c_start(dut):
    yield Timer(I2C_PERIOD / 2)
    dut.sdo_sda = 0
    yield Timer(I2C_PERIOD / 2)
    dut.sck_scl = 0
    yield Timer(I2C_PERIOD / 2)

@cocotb.coroutine
def i2c_stop(dut):
    yield Timer(I2C_PERIOD / 2)
    dut.sdo_sda = 0
    yield Timer(I2C_PERIOD / 2)
    dut.sck_scl = 1
    yield Timer(I2C_PERIOD / 2)
    dut.sdo_sda = BinaryValue("z")
    yield Timer(I2C_PERIOD / 2)

@cocotb.coroutine
def i2c_byte_write(dut, data):
    for i in range(0,8):
        dut.sdo_sda = BinaryValue("z") if (data & 0x80) else 0
        data = data << 1
        dut.sck_scl = 0
        yield Timer(I2C_PERIOD / 2)
        dut.sck_scl = 1
        yield Timer(I2C_PERIOD / 2)
        dut.sck_scl = 0
    dut.sdo_sda = BinaryValue("z")
    yield Timer(I2C_PERIOD / 2)
    dut.sck_scl = 1
    yield ReadOnly()
    if dut.sdo_sda.value.integer != 0:
        print("ack error................")
    yield Timer(I2C_PERIOD / 2)
    dut.sck_scl = 0
    yield Timer(I2C_PERIOD / 2)

@cocotb.coroutine
def i2c_byte_read(dut, is_end):
    r_data = 0
    for i in range(0,8):
        dut.sck_scl = 0
        yield Timer(I2C_PERIOD / 2)
        dut.sck_scl = 1
        yield ReadOnly()
        r_data = (r_data << 1) | (dut.sdo_sda.value.binstr != "0")
        yield Timer(I2C_PERIOD / 2)
        dut.sck_scl = 0
    yield Timer(200000)
    dut.sdo_sda = BinaryValue("z") if is_end else 0 # no ack mean no further read
    yield Timer(I2C_PERIOD / 2)
    dut.sck_scl = 1
    yield Timer(I2C_PERIOD / 2)
    dut.sck_scl = 0
    dut.sdo_sda = BinaryValue("z")
    yield Timer(I2C_PERIOD / 2)
    raise ReturnValue(r_data)

@cocotb.coroutine
def i2c_read(dut, address, len = 1):
    datas = []
    yield i2c_start(dut)
    yield i2c_byte_write(dut, 0xc0)
    yield i2c_byte_write(dut, address)
    yield i2c_stop(dut)
    
    yield i2c_start(dut)
    yield i2c_byte_write(dut, 0xc1)
    while len != 0:
        len -= 1
        ret_val = yield i2c_byte_read(dut, len == 0)
        datas.append(ret_val)
    yield i2c_stop(dut)
    raise ReturnValue(datas)

@cocotb.coroutine
def i2c_write(dut, address, datas):
    yield i2c_start(dut)
    yield i2c_byte_write(dut, 0xc0)
    yield i2c_byte_write(dut, address)
    for data in datas:
        yield i2c_byte_write(dut, data)
    yield i2c_stop(dut)


@cocotb.test()
def test_cdctl_bx(dut):
    """
    test_cdctl_bx
    """
    dut._log.info("test_cdctl_bx start.")
    dut.intf_sel = 0
    dut.addr_sel = 0
    dut.sdo_sda = BinaryValue("z")
    dut.sck_scl = 1

    cocotb.fork(Clock(dut.clk, CLK_PERIOD).start())
    yield Timer(500000) # wait reset

    value = yield i2c_read(dut, REG_VERSION)
    dut._log.info("REG_VERSION: 0x%02x" % int(value[0]))
    value = yield i2c_read(dut, REG_SETTING)
    dut._log.info("REG_SETTING: 0x%02x" % int(value[0]))

    yield i2c_write(dut, REG_SETTING, [BinaryValue("00010001").integer])

    yield i2c_write(dut, REG_PERIOD_LS_H, [0])
    yield i2c_write(dut, REG_PERIOD_LS_L, [39])
    yield i2c_write(dut, REG_PERIOD_HS_H, [0])
    yield i2c_write(dut, REG_PERIOD_HS_L, [3])
    yield i2c_write(dut, REG_FILTER, [0x00])
    # TODO: reset rx...

    yield i2c_write(dut, REG_TX, [0x01])
    yield i2c_write(dut, REG_TX, [0x00])
    yield i2c_write(dut, REG_TX, [0x01, 0xcd])
    #yield i2c_write(dut, REG_TX, [0xcd])

    yield i2c_write(dut, REG_TX_CTRL, [BIT_TX_START | BIT_TX_RST_POINTER])

    
    yield RisingEdge(dut.cdctl_bx_m.cdbus_m.rx_pending)
    value = yield i2c_read(dut, REG_RX, 3)
    print(" ".join([("%02x" % x) for x in value]))
    value = yield i2c_read(dut, REG_RX, 3)
    print(" ".join([("%02x" % x) for x in value]))
    
    
    #yield RisingEdge(dut.cdctl_bx_m.cdbus_m.bus_idle)
    #yield RisingEdge(dut.cdctl_bx_m.cdbus_m.bus_idle)
    yield Timer(15000000)

    yield send_frame(dut, b'\x05\x00\x01\xcd', 39, 3)
    
    yield Timer(50000000)

    dut._log.info("test_cdctl_bx done.")

