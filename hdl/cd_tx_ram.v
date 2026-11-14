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

reg rd_sel;
reg [1:0] unread_cnt;                   // pages waiting to be sent: 0 to 2
wire wr_sel = rd_sel ^ unread_cnt[0];   // the page after them

assign unread = (unread_cnt != 0);
assign wr_full = unread_cnt[1];

wire len_inc = wr_done && !wr_drop && !wr_full; // page submit
wire len_dec = rd_done && unread;               // page sent
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
        unread_cnt <= 0;
    end
    else begin
        // wr_drop removes the page behind the one being sent
        unread_cnt <= ((wr_drop && wr_full) ? 2'd1 : unread_cnt) + len_inc - len_dec;
        if (len_dec)
            rd_sel <= !rd_sel;
    end

endmodule

