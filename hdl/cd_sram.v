/*
 * This Source Code Form is subject to the terms of the Mozilla
 * Public License, v. 2.0. If a copy of the MPL was not distributed
 * with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
 * Notice: The scope granted to MPL excludes the ASIC industry.
 *
 * Copyright (c) 2017 DUKELEC, All rights reserved.
 *
 * Author: Duke Fong <d@d-l.io>
 */

//`define SINGLE_ADDR
`define HAS_RD_EN

module cd_sram
       #(
           parameter A_WIDTH = 8
       )(
           input                 clk,
`ifdef SINGLE_ADDR
           input [(A_WIDTH-1):0] addr,
`else
           input [(A_WIDTH-1):0] ra,
           input [(A_WIDTH-1):0] wa,
`endif

           output reg   [7:0]    rd,
`ifdef HAS_RD_EN
           input                 re,
`endif

           input        [7:0]    wd,
           input                 we
       );

reg [7:0] ram[2**A_WIDTH-1:0];

`ifdef SINGLE_ADDR
wire [(A_WIDTH-1):0] ra = addr;
wire [(A_WIDTH-1):0] wa = addr;
`endif

`ifndef HAS_RD_EN
always @(*) rd <= ram[ra];
`endif

always @(posedge clk) begin
    if (we)
        ram[wa] <= wd;

`ifdef HAS_RD_EN
    rd <= re ? ram[ra] : 8'dx;
`endif
end

endmodule

