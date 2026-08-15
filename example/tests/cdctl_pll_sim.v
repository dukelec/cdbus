/*
 * This Source Code Form is subject to the terms of the CERN Open
 * Hardware Licence Version 2 - Strongly Reciprocal (CERN-OHL-S v2):
 * https://ohwr.org/cern_ohl_s_v2.txt (see the LICENSE file).
 * Notice: The CDBUS Exception (see the LICENSE_EXCEPTION file)
 * grants free commercial use in FPGAs and other programmable logic
 * devices; it does not extend to ASIC design or manufacturing.
 *
 * Copyright (c) 2017-2026 DUKELEC, All rights reserved.
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

