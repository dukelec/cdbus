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

module cd_tx_ram(
           input                 clk,
           input                 reset_n,

           output reg   [7:0]    rd_byte,
           input        [7:0]    rd_addr,
           input                 rd_en,
           input                 rd_done,
           output                unread,

           output                wr_full,
           input       [31:0]    wr_word,
           input        [5:0]    wr_addr,
           input                 wr_en,
           input                 wr_done,
           input                 wr_drop
       );

parameter B_WIDTH = 9; // buffer bit width, 2^9 = 2 x 256 bytes

reg wr_sel;
reg rd_sel;
reg [1:0] dirty;

assign unread = dirty[rd_sel];
assign wr_full = dirty[!rd_sel];
wire [31:0] rd_word;

always @(*)
    case (rd_addr[1:0])
        2'b00:   rd_byte = rd_word[7:0];
        2'b01:   rd_byte = rd_word[15:8];
        2'b10:   rd_byte = rd_word[23:16];
        default: rd_byte = rd_word[31:24];
    endcase

cd_sdpram #(.A_WIDTH(B_WIDTH-2), .D_WIDTH(32)) cd_tx_ram_buf_m(
    .clk(clk),
    .cen(~rd_en & ~wr_en),

    .ra({rd_sel, rd_addr[7:2]}),
    .rd(rd_word),

    .wa({wr_sel, wr_addr}),
    .wd(wr_word),
    .wen(~wr_en)
);


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        rd_sel <= 0;
        wr_sel <= 0;
        dirty <= 0;
    end
    else begin
        if (wr_drop) begin
            dirty[!rd_sel] <= 0;
            wr_sel <= unread ? !rd_sel : rd_sel;
        end
        else if (wr_done) begin
            if (!dirty[wr_sel]) begin
                dirty[wr_sel] <= 1;
                wr_sel <= !wr_sel;
            end
        end

        if (rd_done && dirty[rd_sel]) begin
            dirty[rd_sel] <= 0;
            rd_sel <= !rd_sel;
        end
    end

endmodule

