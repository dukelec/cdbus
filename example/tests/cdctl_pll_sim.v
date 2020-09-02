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

`timescale 1 ns / 1 ps

module cdctl_pll(
        input   REFERENCECLK,
        input   RESET,
        
        output  PLLOUTGLOBAL,
        output  LOCK
    );

wire clk = REFERENCECLK;
assign PLLOUTGLOBAL = clk;

reg reset_n = 1;
assign LOCK = reset_n;

reg [2:0] reset_cnt = 0;
always @(posedge clk) begin
    if (reset_cnt == 3'b010)
        reset_n <= 0;
    else if (reset_cnt == 3'b111)
        reset_n <= 1;

    if (reset_cnt < 3'b111)
        reset_cnt <= reset_cnt + 1;
end 

endmodule

