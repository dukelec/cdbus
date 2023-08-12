[//]: # (IP Core for CDBUS Protocol)

CDBUS IP Core (32-bit version)
=======================================

This document only shows the modifications. For the protocol and original documentation, please refer to the master branch.


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
| INT_FLAG      |  0x0a   | RD     | n/a                    | RX_LEN at byte1, INT_FLAG at byte0        |
| INT_RX        |  0x0b   | RD     | n/a                    | 32-bit width                              |
| INT_TX        |  0x0c   | WR     | n/a                    | 32-bit width                              |
| RX_CTRL       |  0x0d   | WR     | n/a                    |                                           |
| TX_CTRL       |  0x0e   | WR     | n/a                    |                                           |
| FILTER_M      |  0x0f   | RD/WR  | (0xff << 8) \| 0xff    | Two filters at low bytes                  |



## Interface

```verilog
    parameter DIV_LS = 346,         // default: 115200 bps for 40MHz clk
    parameter DIV_HS = 346


    input           clk,            // core clock
    input           reset_n,        // asynch active low reset
    input           chip_select,
    output          irq,            // interrupt output

    // avalon-mm slave interface, read and write without latency
    // support burst read and write (normally for REG_TX and REG_RX)
    // reading REG_RX in burst mode has 1 clock latency
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

Copyright (c) 2017 DUKELEC, All rights reserved.
```

