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

`define HAS_RD_EN

module cd_ram
       #(
           parameter A_WIDTH = 6,
           parameter N_WIDTH = 1,
           parameter MM4RX = 1
       )(
           input                 clk,
           input                 reset_n,

           input [(A_WIDTH-1):0] mm_address,
           input        [3:0]    mm_byteenable,
           input                 mm_read,
           output reg   [31:0]   mm_readdata,
           input                 mm_write,
           input        [31:0]   mm_writedata,

           output reg   [7:0]    rd_byte,
           input [(A_WIDTH+1):0] rd_addr,
           input                 rd_en,
           input                 rd_done,
           input                 rd_done_all,
           output                unread,

           input        [7:0]    wr_byte,
           input [(A_WIDTH+1):0] wr_addr,
           input                 wr_en,

           input                 switch,
           input        [7:0]    wr_flags,
           output reg   [7:0]    rd_flags,
           output reg            switch_fail
       );

reg             [7:0] flags[2**N_WIDTH-1:0];

wire            [7:0] rd_bytes[2**N_WIDTH-1:0][3:0];
`ifdef HAS_RD_EN
wire                  rd_ens[2**N_WIDTH-1:0];
`endif
wire                  wr_ens[2**N_WIDTH-1:0][3:0];
wire  [(A_WIDTH-1):0] rd_addrs[2**N_WIDTH-1:0];
wire  [(A_WIDTH-1):0] wr_addrs[2**N_WIDTH-1:0];

reg     [N_WIDTH-1:0] wr_sel;
reg     [N_WIDTH-1:0] rd_sel;
reg  [2**N_WIDTH-1:0] dirty;

assign unread = (dirty != 0);

genvar i, j;

generate
    for (i = 0; i < 2**N_WIDTH; i = i + 1) begin : cd_sram_array

        if (MM4RX) begin
`ifdef HAS_RD_EN
            assign rd_ens[i] = mm_read & (rd_sel == i);
`endif
            assign rd_addrs[i] = mm_address;
            assign wr_addrs[i] = wr_addr[(A_WIDTH+1):2];
        end
        else begin
`ifdef HAS_RD_EN
            assign rd_ens[i] = (mm_read & (wr_sel == i)) | (rd_en & (rd_sel == i));
`endif
            assign rd_addrs[i] = wr_sel == i ? mm_address : rd_addr[(A_WIDTH+1):2];
            assign wr_addrs[i] = mm_address;
        end

        for (j = 0; j < 4; j = j + 1) begin : cd_sram_array_sub

            if (MM4RX)
                assign wr_ens[i][j] = wr_en & (wr_sel == i) & (wr_addr[1:0] == j);
            else
                assign wr_ens[i][j] = mm_write & (wr_sel == i) & mm_byteenable[j];

            cd_sram #(.A_WIDTH(6)) cd_sram_m(
                .clk(clk),
                .ra(rd_addrs[i]),
                .wa(wr_addrs[i]),
                .rd(rd_bytes[i][j]),
`ifdef HAS_RD_EN
                .re(rd_ens[i]),
`endif
                .wd(MM4RX ? wr_byte : mm_writedata[7+8*j:8*j]),
                .we(wr_ens[i][j])
            );
        end
    end
endgenerate


`ifdef HAS_RD_EN
always @(*) begin
`else
always @(posedge clk) begin
`endif
    rd_byte <= rd_bytes[rd_sel][rd_addr[1:0]];

    if (MM4RX)
        mm_readdata <= {rd_bytes[rd_sel][3], rd_bytes[rd_sel][2], rd_bytes[rd_sel][1], rd_bytes[rd_sel][0]};
    else
        mm_readdata <= {rd_bytes[wr_sel][3], rd_bytes[wr_sel][2], rd_bytes[wr_sel][1], rd_bytes[wr_sel][0]};
end


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

