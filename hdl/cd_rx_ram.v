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

           output       [7:0]    rd_byte,
           input        [7:0]    rd_addr,
           input                 rd_en,
           input                 rd_done,
           input                 rd_done_all,
           output reg            unread,

           output       [7:0]    rd_frm_len, // frame len, include header and crc (<= 256), 0: 1bytes, 255: 256bytes
           output reg            rd_err,

           input        [7:0]    wr_byte,
           input        [7:0]    wr_addr,
           input                 wr_en,

           input                 wr_err,
           input                 switch,
           output reg            switch_fail
       );

parameter S_WIDTH = B_WIDTH - I_WIDTH;  // small block size width, 2^(11-6) = 2^5 = 32 bytes
parameter F_WIDTH = 8 - S_WIDTH;        // frag amount size width, 8-(11-6) = 3, 2^3 x 32 = 8 x 32 = 256 bytes

reg    [I_WIDTH-1:0] wr_sel;
reg    [I_WIDTH-1:0] rd_sel;
reg [2**I_WIDTH-1:0] dirty;

reg  [B_WIDTH-1:0] buf_wr_addr;
wire [B_WIDTH-1:0] buf_rd_addr = (rd_sel << S_WIDTH) + rd_addr; // {rd_sel, {S_WIDTH{1'b0}}}

// has_err[0], frag_count[2:0], len[7:0]
reg  [1+F_WIDTH+8-1:0] idx_table [2**I_WIDTH-1:0];

reg [1+F_WIDTH+8-1:0] idx_rd_val;
wire         [7:0] idx_rval_len    = idx_rd_val[7:0];
wire [F_WIDTH-1:0] idx_rval_amount = idx_rd_val[8+F_WIDTH-1:8];
wire               idx_rval_err    = idx_rd_val[1+F_WIDTH+8-1];

assign rd_frm_len = idx_rval_len;

reg wr_cancel;
reg wr_en_d;
reg wr_err_d;
reg switch_d;
reg [F_WIDTH-1:0] wr_frag_amount;

always @(posedge clk)
    idx_rd_val <= idx_table[rd_sel];


cd_sdpram #(.A_WIDTH(B_WIDTH)) cd_rx_ram_buf_m(
    .clk(clk),
    .cen(~rd_en & ~wr_en_d),

    .ra(buf_rd_addr),
    .rd(rd_byte),

    .wa(buf_wr_addr),
    .wd(wr_byte),
    .wen(~wr_en_d)
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
        rd_err <= 0;
        unread <= 0;
    end
    else begin
        switch_fail <= 0;
        wr_en_d <= 0;
        buf_wr_addr <= (wr_sel << S_WIDTH) + wr_addr;
        switch_d <= switch;
        wr_err_d <= wr_err;
        unread <= dirty[rd_sel]; // 2 clock after write 1 to csr.rx_ctrl.ram_rd_done
        rd_err <= (unread && dirty[rd_sel]) ? idx_rval_err : 0; // 1 clock after unread, don't read int_flag too fast

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
                idx_table[wr_sel] <= {wr_err_d, wr_frag_amount, wr_addr};
                dirty[wr_sel] <= 1;
                wr_sel <= wr_sel + wr_frag_amount + 1'b1; // wr_sel next may equal to rd_sel
            end
            wr_cancel <= 0;
        end

        if (rd_done && dirty[rd_sel]) begin
            dirty[rd_sel] <= 0;
            rd_sel <= rd_sel + 1'b1 + idx_rval_amount;
        end

        if (rd_done_all) begin
            switch_fail <= 0;
            rd_sel <= 0;
            wr_sel <= 0;
            dirty <= 0;
            wr_cancel <= 0;
            switch_d <= 0;
        end
    end

endmodule

