[//]: # (IP Core for CDBUS Protocol)

CDBUS IP Core (32-bit version)
=======================================

This document only shows the modifications. For the protocol and original documentation, please refer to the master branch.


## Registers
 
| Register Name |Addr     | Access | Default                | Description                               | Remarks                       |
|---------------|---------|--------|------------------------|-------------------------------------------|-------------------------------|
| VERSION       |  0x00   | RD     | 0x0d                   | Hardware version                          |                               |
| SETTING       |  0x01   | RD/WR  | 0x10                   | Configs                                   |                               |
| IDLE_WAIT_LEN |  0x02   | RD/WR  | 0x0a                   | How long to enter idle                    |                               |
| TX_PERMIT_LEN |  0x03   | RD/WR  | 0x14                   | How long to allow sending                 |                               |
| MAX_IDLE_LEN  |  0x04   | RD/WR  | 0xc8                   | Max idle for BS mode                      |                               |
| TX_PRE_LEN    |  0x05   | RD/WR  | 0x01                   | Active TX_EN before TX                    |                               |
| FILTER        |  0x06   | RD/WR  | 0xff                   | Set to local address                      |                               |
| DIV_LS        |  0x07   | RD/WR  | 0x015a                 | Low-speed rate setting                    |                               |
| DIV_HS        |  0x08   | RD/WR  | 0x015a                 | High-speed rate setting                   |                               |
| INT_FLAG      |  0x09   | RD     | n/a                    | Status                                    |                               |
| INT_MASK      |  0x0a   | RD/WR  | 0x00                   | Interrupt mask                            |                               |
| RX_CTRL       |  0x0b   | WR     | n/a                    | RX control                                | Bit 0 has no effect           |
| TX_CTRL       |  0x0c   | WR     | n/a                    | TX control                                | Bit 0 has no effect           |
| RX_PAGE_FLAG  |  0x0d   | RD     | n/a                    | RX page flag                              |                               |
| FILTER_M      |  0x0e   | RD/WR  | (0xff << 8) \| 0xff    | Multicast filters                         | Two filters at low bytes      |



## Interface

```verilog
    parameter DIV_LS = 346,         // default: 115200 bps for 40MHz clk
    parameter DIV_HS = 346


    input           clk,            // core clock
    input           reset_n,        // asynch active low reset
    output          irq,            // interrupt output

    // avalon-mm slave interface, read with 1 clock latency, write without latency
    input   [3:0]   csr_address,
    input   [3:0]   csr_byteenable,
    input           csr_read,
    output  [31:0]  csr_readdata,
    input           csr_write,
    input   [31:0]  csr_writedata,
 
    // avalon-mm slave interface, read with 1 clock latency, write without latency
    input   [5:0]   rx_mm_address,
    input   [3:0]   rx_mm_byteenable,
    input           rx_mm_read,
    output  [31:0]  rx_mm_readdata,
    input           rx_mm_write,
    input   [31:0]  rx_mm_writedata,

    // avalon-mm slave interface, read with 1 clock latency, write without latency
    input   [5:0]   tx_mm_address,
    input   [3:0]   tx_mm_byteenable,
    input           tx_mm_read,
    output  [31:0]  tx_mm_readdata,
    input           tx_mm_write,
    input   [31:0]  tx_mm_writedata,

    // connect to external PHY chip, e.g. MAX3485
    input           rx,
    output          tx,
    output          tx_en
```

## License
```
This Source Code Form is subject to the terms of the Mozilla
Public License, v. 2.0. If a copy of the MPL was not distributed
with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
Notice: The scope granted to MPL excludes the ASIC industry.
The CDBUS protocol is royalty-free for everyone except chip manufacturers.

Copyright (c) 2017 DUKELEC, All rights reserved.
```

