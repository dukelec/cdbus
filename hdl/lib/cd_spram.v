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
 * Single Port SRAM
 */

module cd_spram
       #(
           parameter A_WIDTH = 8,
           parameter D_WIDTH = 8
       )(
           input                    clk,
           input                    cen,    // chip enable, active low

           input      [A_WIDTH-1:0] addr,   // address

           output reg [D_WIDTH-1:0] rd,     // read data

           input      [D_WIDTH-1:0] wd,     // write data
           input                    wen     // write enable, active low
       );

reg [D_WIDTH-1:0] ram[2**A_WIDTH-1:0];

always @(posedge clk) begin
    if (!cen) begin
        if (!wen)
            ram[addr] <= wd;

        rd <= ram[addr];
    end
end

endmodule

