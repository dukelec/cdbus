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

wire [7:0] rd_bytes[1:0];
wire [7:0] rw_addr[1:0];

wire rd_ens[1:0];
wire wr_ens[1:0];

reg wr_sel;
reg rd_sel;
reg [1:0] dirty;

assign unread = (dirty != 0);
assign rd_byte = rd_bytes[rd_sel];

genvar i;
generate
    for (i = 0; i < 2; i = i + 1) begin : cd_tx_ram_array
        assign rd_ens[i] = rd_en & (rd_sel == i);
        assign wr_ens[i] = wr_en & (wr_sel == i);
        assign rw_addr[i] = wr_ens[i] ? wr_addr : rd_addr;

        cd_spram cd_spram_m(
            .clk(clk),
            .cen(~rd_ens[i] & ~wr_ens[i]),
            .addr(rw_addr[i]),
            .rd(rd_bytes[i]),
            .wd(wr_byte),
            .wen(~wr_ens[i])
        );
    end
endgenerate


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

