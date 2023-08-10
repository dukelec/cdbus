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
           parameter N_WIDTH = 3
       )(
           input                 clk,
           input                 reset_n,

           output       [7:0]    rd_byte,
           input        [7:0]    rd_addr,
           input                 rd_en,
           input                 rd_done,
           input                 rd_done_all,
           output                unread,

           input        [7:0]    wr_byte,
           input        [7:0]    wr_addr,
           input                 wr_en,

           input                 switch,
           input        [7:0]    wr_flags,
           output reg   [7:0]    rd_flags,
           output reg            switch_fail
       );

reg  [7:0] flags[2**N_WIDTH-1:0];
wire [7:0] rd_bytes[2**N_WIDTH-1:0];
wire [7:0] rw_addr[2**N_WIDTH-1:0];

wire rd_ens[2**N_WIDTH-1:0];
wire wr_ens[2**N_WIDTH-1:0];

reg     [N_WIDTH-1:0] wr_sel;
reg     [N_WIDTH-1:0] rd_sel;
reg  [2**N_WIDTH-1:0] dirty;

assign unread = (dirty != 0);
assign rd_byte = rd_bytes[rd_sel];

genvar i;
generate
    for (i = 0; i < 2**N_WIDTH; i = i + 1) begin : cd_rx_ram_array
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
        switch_fail <= 0;
        rd_sel <= 0;
        wr_sel <= 0;
        dirty <= 0;
    end
    else begin
        switch_fail <= 0;
        rd_flags <= flags[rd_sel];

        if (switch) begin
            if (dirty[wr_sel + 1'b1]) begin
                switch_fail <= 1;
            end
            else begin
                dirty[wr_sel] <= 1;
                flags[wr_sel] <= wr_flags;
                wr_sel <= wr_sel + 1'b1;
            end
        end

        if (rd_done && dirty[rd_sel]) begin
            dirty[rd_sel] <= 0;
            rd_sel <= rd_sel + 1'b1;
        end

        if (rd_done_all) begin
            switch_fail <= 0;
            rd_sel <= 0;
            wr_sel <= 0;
            dirty <= 0;
        end
    end

endmodule

