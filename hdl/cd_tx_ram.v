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

           output       [7:0]    rd_byte,
           input        [7:0]    rd_addr,
           input                 rd_en,
           input                 rd_done,
           output                unread,

           input        [7:0]    wr_byte,
           input        [7:0]    wr_addr,
           input                 wr_en,

           input                 switch
       );

parameter B_WIDTH = 9; // buffer bit width, 2^9 = 2 x 256 bytes

reg wr_sel;
reg rd_sel;
reg [1:0] dirty;

assign unread = dirty[rd_sel]; // better than (dirty != 0)


`ifdef SPRAM_ONLY
// when there is a read/write conflict, writing is delayed
// which is suitable for interfaces such as spi

reg  [8:0] rd_addr_bk;
wire [7:0] rd_byte_ori;
reg  [7:0] rd_byte_bk;

reg wr_en_bk;
reg [8:0] wr_addr_bk; // optional
reg [7:0] wr_byte_bk; // optional for spi

reg  wr_en_final_bk;
wire wr_en_final = rd_addr_bk == {rd_sel, rd_addr} ? wr_en_bk : 0;
assign rd_byte = wr_en_final_bk ? rd_byte_bk : rd_byte_ori;

always @(posedge clk) begin
    wr_en_final_bk <= wr_en_final;
    rd_byte_bk <= wr_en_final_bk ? rd_byte_bk : rd_byte_ori;
    
    rd_addr_bk <= {rd_sel, rd_addr};
end

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        wr_en_bk <= 0;
    end
    else begin
        if (wr_en) begin
            wr_en_bk <= 1;
            wr_addr_bk <= {wr_sel, wr_addr};
            wr_byte_bk <= wr_byte;
        end
        else if (wr_en_final) begin
            wr_en_bk <= 0;
        end
    end

cd_spram #(.A_WIDTH(B_WIDTH)) cd_tx_ram_buf_m(
    .clk(clk),
    .cen(~rd_en & ~wr_en_final),

    .addr(wr_en_final ? wr_addr_bk : {rd_sel, rd_addr}),

    .rd(rd_byte_ori),

    .wd(wr_byte_bk),
    .wen(~wr_en_final)
);

`else
cd_sdpram #(.A_WIDTH(B_WIDTH)) cd_tx_ram_buf_m(
    .clk(clk),
    .cen(~rd_en & ~wr_en),

    .ra({rd_sel, rd_addr}),
    .rd(rd_byte),

    .wa({wr_sel, wr_addr}),
    .wd(wr_byte),
    .wen(~wr_en)
);
`endif


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        rd_sel <= 0;
        wr_sel <= 0;
        dirty <= 0;
    end
    else begin
        if (switch) begin
            if (!dirty[!wr_sel]) begin
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

