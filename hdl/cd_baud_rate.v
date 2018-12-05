/*
 * This Source Code Form is subject to the terms of the Mozilla
 * Public License, v. 2.0. If a copy of the MPL was not distributed
 * with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
 * Notice: The scope granted to MPL excludes the ASIC industry.
 *
 * Copyright (c) 2017 DUKELEC, All rights reserved.
 *
 * Author: Duke Fong <duke@dukelec.com>
 */

module cd_baud_rate
   #(
        parameter INIT_VAL = 0,
        parameter FOR_TX = 0
   )(
        input               clk,
        input               sync,   // reset counters to zero

        input       [15:0]  div_ls, // low speed
        input       [15:0]  div_hs, // high speed
        input               sel,

        output reg          inc,
        output reg          cap
    );

wire [15:0] div = sel ? div_hs : div_ls;
reg [15:0] cnt = 0;

always @(posedge clk) begin
    inc <= 0;
    cap <= 0;

    if (sync) begin
        cnt <= INIT_VAL;
    end
    else begin
        cnt <= cnt + 1'b1;

        if (FOR_TX) begin // at 3/4 position
            if (cnt == div - div[15:2])
                cap <= 1;
        end
        else begin // at 1/2 position
            if (cnt == {1'd0, div[15:1]})
                cap <= 1;
        end

        if (cnt >= div) begin
            cnt <= 0;
            inc <= 1;
        end
    end
end

endmodule

