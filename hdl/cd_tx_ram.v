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

module cd_tx_ram(
           input                 clk,
           input                 reset_n,

           output       [7:0]    rd_byte,
           input        [7:0]    rd_addr,
           input                 rd_en,
           input                 rd_done,
           output                unread,

           output                wr_full,
           input        [7:0]    wr_byte,
           input        [7:0]    wr_addr,
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


cd_sdpram #(.A_WIDTH(B_WIDTH)) cd_tx_ram_buf_m(
    .clk(clk),
    .cen(~rd_en & ~wr_en),

    .ra({rd_sel, rd_addr}),
    .rd(rd_byte),

    .wa({wr_sel, wr_addr}),
    .wd(wr_byte),
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

