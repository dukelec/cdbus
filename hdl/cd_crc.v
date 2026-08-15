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

