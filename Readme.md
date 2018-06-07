[//]: # (IP Core for CDBUS Protocol)

CDBUS IP Core
=======================================

1. [CDBUS Protocol](#cdbus-protocol)
2. [Block Diagram](#block-diagram)
3. [Registers](#registers)
4. [Interface](#interface)
5. [Examples](#examples)
6. [Simulation](#simulation)
7. [Ready To Use Devices](#ready-to-use-devices)
8. [License](#license)


## CDBUS Protocol

CDBUS is a protocol for Asynchronous Serial Communication,
it has a 3-byte header: `[src_addr, dst_addr, data_len]`, then user data, and finally 2 bytes of CRC.

It's suitable for one-to-one communication, e.g. UART or RS232.
In this case, the address for each side are usually carefully selected and fixed,
e.g: `[0x55, 0xaa, data_len, ...]`, and the backward is: `[0xaa, 0x55, data_len, ...]`.

The CDBUS protocol is more valuable for bus communication, e.g. RS485 or Single Line UART.
In this case:

* It introduces an arbitration mechanism that automatically avoids conflicts like the CAN bus.
* Support dual baud rate, provide high speed communication, maximum rate ≥ 10 Mbps.
* Support broadcast (by set `dst_addr` to `255`).
* Max payload data size is 253 byte (you can increase it to 255 byte, but not recommended).
* Hardware packing, unpacking, verification and filtering, save your time and CPU usage.
* Backward compatible with traditional RS485 hardware (still retains arbitration function).

The protocol example timing, include only one byte user data:  
(How long to enter idle and how long to allow sending can be set.)

![protocol](docs/img/protocol.svg)

Tips:
 - When high-priority node send unimportant data, the transmission wait time (TX_WAIT_LEN) can be dynamically increased.

Arbitration example:

<img alt="arbitration" src="docs/img/arbitration.svg" width="75%">

The idea of CDBUS was first designed and implemented by me in 2009.


## Block Diagram

<img alt="block_diagram" src="docs/img/block_diagram.svg" width="100%">

#### Operation

<img alt="operation" src="docs/img/operation.gif" width="100%">


## Registers
 
| Register Name |Addr[7:0]| Access | Default         | Description                   | Remarks         |
|---------------|---------|--------|-----------------|-------------------------------|-----------------|
| VERSION       |  0x00   | RD     | 0x05            | Hardware version              |                 |
| SETTING       |  0x01   | RD/WR  | 0x10            | Configs                       |                 |
| IDLE_WAIT_LEN |  0x02   | RD/WR  | 0x0a (10 bit)   | How long to enter idle        |                 |
| TX_WAIT_LEN   |  0x03   | RD/WR  | 0x14 (20 bit)   | How long to allow sending     |                 |
| FILTER        |  0x04   | RD/WR  | 0xff            | Receive filter                |                 |
| DIV_LS_L      |  0x05   | RD/WR  | 0x5a            | Low-speed rate setting        |                 |
| DIV_LS_H      |  0x06   | RD/WR  | 0x01            |                               |                 |
| DIV_HS_L      |  0x07   | RD/WR  | 0x5a            | High-speed rate setting       |                 |
| DIV_HS_H      |  0x08   | RD/WR  | 0x01            |                               |                 |
| INT_FLAG      |  0x09   | RD     | n/a             | Status                        |                 |
| INT_MASK      |  0x0a   | RD/WR  | 0x00            | Interrupt mask                |                 |
| RX            |  0x0b   | RD     | n/a             | Read RX page                  |                 |
| TX            |  0x0c   | WR     | n/a             | Write TX page                 |                 |
| RX_CTRL       |  0x0d   | WR     | n/a             | RX control                    |                 |
| TX_CTRL       |  0x0e   | WR     | n/a             | TX control                    |                 |
| RX_ADDR       |  0x0f   | RD/WR  | 0x00            | RX page read pointer          | Uncommonly used |
| RX_PAGE_FLAG  |  0x10   | RD     | n/a             | RX page flag                  | For debugging   |


**SETTING:**

| FIELD   | DESCRIPTION                                       |
|-------- |---------------------------------------------------| 
| [0]     | Enable push-pull output for tx and tx_en pin      |
| [1]     | Invert tx output                                  |
| [2]     | Disable hardware CRC                              |
| [3]     | Save broken frame                                 |
| [5:4]   | tx_en delay before tx output in traditional mode  |
| [6]     | Disable arbitration for traditional mode          |

**FILTER:**

Match from top to bottom:

| SRC_ADDR  | DST_ADDR | FILTER       | Receive or drop | Remarks          |
|---------- |----------|--------------|-----------------|------------------|
| not care  | not care | 255          | Receive         | Promiscuous mode |
| = FILTER  | not care | != 255       | Drop            | Avoid loopback   |
| != FILTER | 255      | not care     | Receive         | Broadcast        |
| != FILTER | != 255   | = DST_ADDR   | Receive         |                  |
| not care  | != 255   | != DST_ADDR  | Drop            |                  |

**DIV_xx_x:**

Baud rate divider value:
DIV_xx[15:0] = sys_freq ÷ baud_rate − 1

**INT_FLAG:**

| FIELD   | DESCRIPTION                                  |
|-------- |----------------------------------------------| 
| [0]     | 1: Bus in IDLE mode                          |
| [1]     | 1: RX page ready for read                    |
| [2]     | 1: RX lost: no empty page for RX             |
| [3]     | 1: RX error: frame broken                    |
| [4]     | 1: TX page released by hardware              |
| [5]     | 1: TX collision detected                     |
| [6]     | 1: TX error: conflict continued for 16 times |

**INT_MASK:**

Output of irq = ((INT_FLAG & INT_MASK) != 0).

**RX_CTRL:**

| FIELD   | DESCRIPTION                 |
|-------- |-----------------------------| 
| [0]     | Reset RX page read pointer  |
| [1]     | Switch RX page              |
| [2]     | Clear RX lost flag          |
| [3]     | Clear RX error flag         |
| [4]     | Reset RX block              |

**TX_CTRL:**

| FIELD   | DESCRIPTION                 |
|-------- |-----------------------------| 
| [0]     | Reset TX page write pointer |
| [1]     | Switch TX page              |
| [2]     | Clear TX collision flag     |
| [3]     | Clear TX error flag         |
| [4]     | Abort TX                    |

**RX_PAGE_FLAG:**

Value zero indicate the frame in current RX page is correct;  
Non-zero indicate the pointer of last received byte of the disturbed frame, include CRC.


## Interface

```verilog
    parameter DIV_LS = 346,         // default: 115200 bps for 40MHz clk
    parameter DIV_HS = 346


    input           clk,            // core clock
    input           reset_n,        // asynch active low reset

    // avalon-mm slave interface, read and write without latency
    // support burst read and write (normally for REG_TX and REG_RX)
    input   [4:0]   csr_address,
    input           csr_read,
    output  [7:0]   csr_readdata,
    input           csr_write,
    input   [7:0]   csr_writedata,

    output          irq,            // interrupt output

    // connect to external PHY chip, e.g. MAX3485
    input           rx,
    output          tx,
    output          tx_en
```


## Examples
 
```python
    # Configuration
    
    write(REG_SETTING, [0x01])                  # Enable push-pull output
    
    
    # TX
    
    write(REG_TX, [0x0c, 0x0d, 0x01, 0xcd])     # Write frame without CRC
    while (read(REG_INT_FLAG) & 0x10) == 0:     # Make sure we can successfully switch to the next page
        pass
    write(REG_TX_CTRL, [0x02])                  # Trigger send by switching TX page
    
    
    # RX
    
    while (read(REG_INT_FLAG) & 0x02) == 0:     # Wait for RX page ready
        pass
    header = read(REG_TX, len=3)
    data = read(REG_TX, len=header[2])
    write(REG_RX_CTRL, [0x02])                  # Finish read by switching RX page

```


## Simulation
Install `iverilog` (>= v10) and `cocotb`, goto `tests/` folder, then type the command:
```sh
    $ COCOTB=/path/to/cocotb make
```
Then you can checkout the waveform `cdbus.vcd` by GTKWave.


## Ready To Use Devices

The CDCTL controller family uses the CDBUS IP Core, which provide SPI, I<sup>2</sup>C and PCIe peripheral interfaces.  
E.g. The tiny CDCTL-Bx module support both SPI and I<sup>2</sup>C interfaces:  
<img alt="cdctl_bx" src="docs/img/cdctl_bx.jpg" width="80%">

For more information, visit: http://dukelec.com

## License
```
This Source Code Form is subject to the terms of the Mozilla
Public License, v. 2.0. If a copy of the MPL was not distributed
with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
Notice: The scope granted to MPL excludes the ASIC industry.
The CDBUS protocol is royalty-free for everyone except chip manufacturers.

Copyright (c) 2017 DUKELEC, All rights reserved.
```

