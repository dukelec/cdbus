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

module cd_baud_rate
   #(
        parameter INIT_VAL = 1,
        parameter FOR_TX = 0
   )(
        input               clk,
        input               sync,   // reset counters to INIT_VAL
        input               sync_3x,

        input       [15:0]  div_ls, // low speed
        input       [15:0]  div_hs, // high speed
        input               sel,

        output              inc,
        output              cap
    );

reg inc_d;
reg cap_d;
assign inc = inc_d & !sync & !sync_3x;
assign cap = cap_d & !sync & !sync_3x;

wire [15:0] div = sel ? div_hs : div_ls;
reg [15:0] cnt = 0;

always @(posedge clk) begin
    inc_d <= 0;
    cap_d <= 0;

    if (sync) begin
        cnt <= INIT_VAL;
    end
    else if (sync_3x) begin
        cnt <= INIT_VAL + 1;
        if (INIT_VAL == div[15:1])
            cap_d <= 1;
    end
    else begin
        cnt <= cnt + 1'b1;

        if (FOR_TX) begin // at 3/4 position
            if (cnt == div - div[15:2])
                cap_d <= 1;
        end
        else begin // at 1/2 position
            if (cnt == {1'd0, div[15:1]})
                cap_d <= 1;
        end

        if (cnt >= div) begin
            cnt <= 0;
            inc_d <= 1;
        end
    end
end

endmodule

