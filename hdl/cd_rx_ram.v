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

module cd_rx_ram
       #(
           parameter I_WIDTH = 6,   // index bit width, 2^6 = 64 entries
           parameter B_WIDTH = 11   // buffer bit width, 2^11 = 2048 bytes
       )(
           input                 clk,
           input                 reset_n,

           output      [31:0]    rd_word,
           input        [5:0]    rd_addr,
           input                 rd_en,
           input                 rd_done,
           input                 rd_done_all,
           output reg            unread,
           output reg [I_WIDTH-1:0] unread_len,

           // user data len (0: 0 bytes, 253: 253 bytes), or: frame len, include crc (0: 1bytes, 255: 256bytes)
           output       [7:0]    rd_len,
           output                rd_err,

           input        [7:0]    wr_byte,
           input        [7:0]    wr_addr,
           input                 wr_en,

           input                 wr_err,
           input        [7:0]    wr_len,
           input                 switch,
           output reg            switch_fail
       );

parameter S_WIDTH = B_WIDTH - I_WIDTH;  // small block size width, 2^(11-6) = 2^5 = 32 bytes
parameter F_WIDTH = 8 - S_WIDTH;        // frag amount size width, 8-(11-6) = 3, 2^3 x 32 = 8 x 32 = 256 bytes

reg    [I_WIDTH-1:0] wr_sel;
reg    [I_WIDTH-1:0] rd_sel;
reg [2**I_WIDTH-1:0] dirty;

reg  [B_WIDTH-1:0] buf_wr_addr;
wire [B_WIDTH-1:0] buf_rd_addr = (rd_sel << S_WIDTH) + (rd_addr << 2); // {rd_sel, {S_WIDTH{1'b0}}}

wire [F_WIDTH+8:0] idx_rd_val; // {err_flag, frag_amount, len}
wire [F_WIDTH-1:0] idx_frag_amount = idx_rd_val[F_WIDTH+7:8];
assign rd_len = idx_rd_val[7:0];
assign rd_err = idx_rd_val[F_WIDTH+8];

reg [31:0] wr_word;
reg wr_cancel;
reg wr_en_d;
reg wr_err_d;
reg switch_d;
reg [F_WIDTH-1:0] wr_frag_amount;

always @(posedge clk)
    unread <= dirty[rd_sel];

always @(posedge clk)
    if (wr_en) begin
        case (wr_addr[1:0])
            2'b00:   wr_word = {24'bx, wr_byte};
            2'b01:   wr_word = {16'bx, wr_byte, wr_word[7:0]};
            2'b10:   wr_word = {8'bx, wr_byte, wr_word[15:0]};
            default: wr_word = {wr_byte, wr_word[23:0]};
        endcase
    end


cd_sdpram #(.A_WIDTH(B_WIDTH-2), .D_WIDTH(32)) cd_rx_ram_buf_m(
    .clk(clk),
    .cen(~rd_en & ~wr_en_d),

    .ra(buf_rd_addr[B_WIDTH-1:2]),
    .rd(rd_word),

    .wa(buf_wr_addr[B_WIDTH-1:2]),
    .wd(wr_word),
    .wen(~wr_en_d)
);

cd_sdpram #(.A_WIDTH(I_WIDTH), .D_WIDTH(F_WIDTH+9)) cd_rx_idx_table_m(
    .clk(clk),
    .cen(~dirty[rd_sel] & ~(switch_d & ~wr_cancel)),

    .ra(rd_sel),
    .rd(idx_rd_val),

    .wa(wr_sel),
    .wd({wr_err_d, wr_frag_amount, wr_len}),
    .wen(~(switch_d & ~wr_cancel))
);


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        switch_fail <= 0;
        rd_sel <= 0;
        wr_sel <= 0;
        dirty <= 0;
        wr_cancel <= 0;
        wr_en_d <= 0;
        wr_frag_amount <= 0;
        switch_d <= 0;
        wr_err_d <= 0;
        unread_len <= 0;
    end
    else begin
        switch_fail <= 0;
        wr_en_d <= 0;
        buf_wr_addr <= (wr_sel << S_WIDTH) + wr_addr;
        switch_d <= switch;
        wr_err_d <= wr_err;

        if (wr_en & !wr_cancel) begin
            if (dirty[wr_sel + wr_addr[7:S_WIDTH]]) begin
                wr_cancel <= 1;
            end
            else begin
                wr_en_d <= 1;
                wr_frag_amount <= wr_addr[7:S_WIDTH]; // 0 ~ 7
            end
        end

        if (switch_d) begin
            if (wr_cancel) begin
                switch_fail <= 1;
            end
            else begin
                dirty[wr_sel] <= 1;
                wr_sel <= wr_sel + wr_frag_amount + 1'b1; // wr_sel next may equal to rd_sel
                unread_len <= unread_len + 1;
                // write idx_table here
            end
            wr_cancel <= 0;
        end

        if (rd_done && dirty[rd_sel]) begin
            dirty[rd_sel] <= 0;
            rd_sel <= rd_sel + 1'b1 + idx_frag_amount;
            unread_len <= unread_len - 1;
        end

        if (rd_done_all) begin
            switch_fail <= 0;
            rd_sel <= 0;
            wr_sel <= 0;
            dirty <= 0;
            wr_cancel <= 0;
            switch_d <= 0;
            unread_len <= 0;
        end
    end

endmodule

