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
 * MODBUS CRC LSB first:
 *   https://en.wikipedia.org/wiki/Modbus
 */

module cd_crc(
    input               clk,
    input               clean,
    input               data_clk,
    input               data_in,
    output wire [15:0]  crc_out
);

reg [0:15] lfsr; // reverse bits
assign crc_out = lfsr;

always @ (posedge clk)
    if (clean) begin
        lfsr <= 16'hFFFF;
    end
    else if (data_clk) begin
        lfsr[0]  <= data_in ^ lfsr[15];
        lfsr[1]  <= lfsr[0];
        lfsr[2]  <= lfsr[1] ^ data_in ^ lfsr[15];
        lfsr[3]  <= lfsr[2];
        lfsr[4]  <= lfsr[3];
        lfsr[5]  <= lfsr[4];
        lfsr[6]  <= lfsr[5];
        lfsr[7]  <= lfsr[6];
        lfsr[8]  <= lfsr[7];
        lfsr[9]  <= lfsr[8];
        lfsr[10] <= lfsr[9];
        lfsr[11] <= lfsr[10];
        lfsr[12] <= lfsr[11];
        lfsr[13] <= lfsr[12];
        lfsr[14] <= lfsr[13];
        lfsr[15] <= lfsr[14] ^ data_in ^ lfsr[15];
    end

endmodule

