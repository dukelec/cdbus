/*
 * This Source Code Form is subject to the terms of the Mozilla
 * Public License, v. 2.0. If a copy of the MPL was not distributed
 * with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
 * Notice: The scope granted to MPL excludes the ASIC industry.
 *
 * Copyright (c) 2017 DUKELEC, All rights reserved.
 *
 * Author: Duke Fong <d@d-l.io>
 *
 * Simple Dual-Port SRAM
 */

module cd_sdpram
       #(
           parameter A_WIDTH = 8,
           parameter D_WIDTH = 8
       )(
           input                    clk,
           input                    cen,    // chip enable, active low

           input      [A_WIDTH-1:0] ra,     // read addr
`ifdef CD_SPRAM_ONLY
           output     [D_WIDTH-1:0] rd,     // read data
`else
           output reg [D_WIDTH-1:0] rd,
`endif

           input      [A_WIDTH-1:0] wa,     // write addr
           input      [D_WIDTH-1:0] wd,     // write data
           input                    wen     // write enable, active low
       );

`ifdef CD_SPRAM_ONLY
// on read-write conflict, read delays 1 clock

wire [D_WIDTH-1:0] rd_ori;
reg  [D_WIDTH-1:0] rd_bk;
reg wen_d;

always @(posedge clk) begin
    wen_d <= wen;
    if (wen_d)
        rd_bk <= rd_ori;
end

assign rd = wen_d ? rd_ori : rd_bk;

cd_spram #(.A_WIDTH(A_WIDTH), .D_WIDTH(D_WIDTH)) cd_spram_m(
    .clk(clk),
    .cen(cen & wen),

    .addr(wen ? ra : wa),

    .rd(rd_ori),

    .wd(wd),
    .wen(wen)
);

`else

reg [D_WIDTH-1:0] ram[2**A_WIDTH-1:0];

always @(posedge clk) begin
    if (!cen) begin
        if (!wen)
            ram[wa] <= wd;

        rd <= ram[ra];
    end
end

`endif

endmodule

