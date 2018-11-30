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

module baud_rate_gen(
        input               clk,
        input               sync,   // reset counters to zero

        input       [15:0]  div_ls, // low speed, range: ['h0000, 'hfffb]
        input       [15:0]  div_hs, // high speed, same range
        input               sel,
        
        output reg  [1:0]   cnt,
        output reg          inc
    );

wire [13:0] mantissa_ori = sel ? div_hs[15:2] : div_ls[15:2];
wire [13:0] mantissa_add1 = mantissa_ori + 1;
wire [1:0] fraction = sel ? div_hs[1:0] : div_ls[1:0];

reg [3:0] interpolation;
reg [13:0] mantissa_cnt;

wire [13:0] mantissa = interpolation[cnt] ? mantissa_add1 : mantissa_ori;


always @(fraction)
    case (fraction)
        2'b00:
            interpolation = 4'b0000;
        2'b01:
            interpolation = 4'b0001;
        2'b10:
            interpolation = 4'b0101;
        2'b11:
            interpolation = 4'b0111;
    endcase


always @(posedge clk)
    if (sync) begin
        cnt <= 0;
        inc <= 0;
        mantissa_cnt <= 0;
    end
    else begin
        inc <= 0;
        mantissa_cnt <= mantissa_cnt + 1'b1;
        
        if (mantissa_cnt >= mantissa) begin
            mantissa_cnt <= 0;
            cnt <= cnt + 1'b1;
            inc <= 1;
        end
    end

endmodule

