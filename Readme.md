[//]: # (IP Core for CDBUS Protocol)

CDBUS IP Core (32-bit version)
=======================================

This document only describes the modifications. For the full protocol and documentation, please refer to the 8-bit version.


## Registers
 
| Register Name |Addr     | Access | Default                | Remarks                                   |
|---------------|---------|--------|------------------------|-------------------------------------------|
| VERSION       |  0x00   | RD     | 0x0f                   |                                           |
| SETTING       |  0x01   | RD/WR  | 0x10                   |                                           |
| IDLE_WAIT_LEN |  0x02   | RD/WR  | 0x0a                   |                                           |
| TX_PERMIT_LEN |  0x03   | RD/WR  | 0x14                   |                                           |
| MAX_IDLE_LEN  |  0x04   | RD/WR  | 0xc8                   |                                           |
| TX_PRE_LEN    |  0x05   | RD/WR  | 0x01                   |                                           |
| FILTER        |  0x06   | RD/WR  | 0xff                   |                                           |
| DIV_LS        |  0x07   | RD/WR  | 0x015a                 |                                           |
| DIV_HS        |  0x08   | RD/WR  | 0x015a                 |                                           |
| INT_MASK      |  0x09   | RD/WR  | 0x00                   |                                           |
| INT_FLAG      |  0x0a   | RD     | n/a                    | RX_LEN: byte 2, INT_FLAG: bytes 0-1       |
| DAT           |  0x0b   | RD/WR  | n/a                    | 32-bit width                              |
| CTRL          |  0x0c   | WR     | n/a                    |                                           |
| FILTER_M      |  0x0f   | RD/WR  | (0xff << 8) \| 0xff    | Two filters in lower 2 bytes              |



## Interface

```verilog
    parameter DIV_LS = 346,         // default: 115200 bps for 40MHz clk
    parameter DIV_HS = 346


    input           clk,            // core clock
    input           reset_n,        // asynch active low reset
    input           chip_select,
    output          irq,            // interrupt output

    // supports zero-latency read/write and burst transfers
    input   [3:0]   csr_address,
    input           csr_read,
    output [31:0]   csr_readdata,
    input           csr_write,
    input  [31:0]   csr_writedata,

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

Copyright (c) 2025 DUKELEC, All rights reserved.
```

