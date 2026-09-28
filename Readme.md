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
| DAT_HOLD      |  0x0d   | RD/WR  | n/a                    | Same as DAT, but keeps the page open      |
| RX_ADDR       |  0x0e   | WR     | n/a                    | Read position of the RX page, in words    |
| FILTER_M      |  0x0f   | RD/WR  | 0xffffffff             | [MSK1, MSK0, M1, M0]                      |

DAT_HOLD and RX_ADDR only differ from the 8-bit version in that the RX_ADDR value is a 32-bit word offset instead of a byte offset.



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

**chip_select:**

Besides the transfer-based behaviour for interfaces like SPI (enabled by `CD_CHIP_SELECT`),
`chip_select` gates the read port of the RX RAM to reduce power consumption:
the RX RAM is only read while it is high, and the data is available one clock after it goes high.

For SoC integration, drive it from the bus select of this peripheral, e.g. `psel` of APB or `hsel` of AHB,
both of which are asserted one clock before the data is sampled.
For a bus that samples read data in the same clock as the select, assert it one clock earlier (e.g. from the address decode),
or simply tie it high at the cost of the RX RAM being read every clock.

**CD_CSR_NO_LATENCY:**

Without this define, DAT reads on consecutive clocks return the same word, since the RX RAM needs one clock per word.
Define it to allow zero-wait-state bursts from a synchronous host such as a SoC bus or DMA.
It is not safe for an asynchronous host such as SPI, since the read data can glitch when `csr_read` toggles.


## License
```
This Source Code Form is subject to the terms of the CERN Open
Hardware Licence Version 2 - Strongly Reciprocal (CERN-OHL-S v2):
https://ohwr.org/cern_ohl_s_v2.txt (see the LICENSE file).
Notice: The CDBUS Exception (see the LICENSE_EXCEPTION file)
grants free commercial use in FPGAs and other programmable logic
devices; it does not extend to ASIC design or manufacturing.

Copyright (c) 2017-2026 DUKELEC, All rights reserved.
```

