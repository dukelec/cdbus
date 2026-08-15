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
           output reg [D_WIDTH-1:0] rd,     // read data

           input      [A_WIDTH-1:0] wa,     // write addr
           input      [D_WIDTH-1:0] wd,     // write data
           input                    wen     // write enable, active low
       );

reg [D_WIDTH-1:0] ram[2**A_WIDTH-1:0];

always @(posedge clk) begin
    if (!cen) begin
        if (!wen)
            ram[wa] <= wd;

        rd <= ram[ra];
    end
end

endmodule

