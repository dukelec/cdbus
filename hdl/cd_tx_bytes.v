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

module cd_tx_bytes(
        input               clk,
        input               reset_n,

        input               user_crc,
        input               abort,

        output reg  [7:0]   data,
        output              has_data,
        input               ack_data,
        output reg          is_crc_byte,
        output reg          is_last_byte,
        input       [15:0]  crc_data,

        input               ram_unread,
        input       [7:0]   ram_rd_byte,
        output      [7:0]   ram_rd_addr,
        output              ram_rd_en,
        output reg          ram_rd_done
    );

assign has_data = ram_unread;
assign ram_rd_en = ram_unread;

reg [8:0] byte_cnt;
assign ram_rd_addr = byte_cnt[7:0];
reg [7:0] data_len; // backup 3rd byte


always @(posedge clk)
    if (!ram_unread || ram_rd_done) begin
        byte_cnt <= 0;
        data_len <= 0;
        is_crc_byte <= 0;
        is_last_byte <= 0;
    end
    else begin
        data <= ram_rd_byte;

        if (byte_cnt == 2)
            data_len <= ram_rd_byte;

        // we have enough time to change the byte which send at second bit
        else if (byte_cnt == data_len + 3) begin
            if (!user_crc)
                data <= crc_data[7:0];
            is_crc_byte <= 1;
        end
        else if (byte_cnt == data_len + 4) begin
            if (!user_crc)
                data <= crc_data[15:8];
            is_last_byte <= 1;
        end

        if (ack_data)
            byte_cnt <= byte_cnt + 1'd1;
    end


always @(posedge clk) begin
    ram_rd_done <= 0;
    if (abort || (is_last_byte && ack_data))
        ram_rd_done <= 1;
end

endmodule

