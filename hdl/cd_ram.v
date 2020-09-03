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

//`define SINGLE_ADDR
`define HAS_RD_EN

module cd_ram
       #(
           parameter A_WIDTH = 8,
           parameter N_WIDTH = 1
       )(
           input                 clk,
           input                 reset_n,

           output reg   [7:0]    rd_byte,
           input [(A_WIDTH-1):0] rd_addr,
           input                 rd_en,
           input                 rd_done,
           input                 rd_done_all,
           output                unread,

           input        [7:0]    wr_byte,
           input [(A_WIDTH-1):0] wr_addr,
           input                 wr_en,

           input                 switch,
           input        [7:0]    wr_flags,
           output reg   [7:0]    rd_flags,
           output reg            switch_fail
       );

reg             [7:0] flags[2**N_WIDTH-1:0];

wire            [7:0] rd_bytes[2**N_WIDTH-1:0];
`ifdef HAS_RD_EN
wire                  rd_ens[2**N_WIDTH-1:0];
`endif
wire                  wr_ens[2**N_WIDTH-1:0];
`ifdef SINGLE_ADDR
wire [2**A_WIDTH-1:0] rw_addr[2**N_WIDTH-1:0];
`endif

reg     [N_WIDTH-1:0] wr_sel;
reg     [N_WIDTH-1:0] rd_sel;
reg  [2**N_WIDTH-1:0] dirty;

assign unread = (dirty != 0);


genvar i;

generate
    for (i = 0; i < 2**N_WIDTH; i = i + 1) begin : cd_sram_array
`ifdef HAS_RD_EN
        assign rd_ens[i] = rd_en & (rd_sel == i);
`endif
        assign wr_ens[i] = wr_en & (wr_sel == i);
`ifdef SINGLE_ADDR
        assign rw_addr[i] = wr_ens[i] ? wr_addr : rd_addr;
`endif

        cd_sram cd_sram_m(
            .clk(clk),
`ifdef SINGLE_ADDR
            .addr(rw_addr[i]),
`else
            .ra(rd_addr),
            .wa(wr_addr),
`endif
            .rd(rd_bytes[i]),
`ifdef HAS_RD_EN
            .re(rd_ens[i]),
`endif
            .wd(wr_byte),
            .we(wr_ens[i])
        );
    end
endgenerate


`ifdef HAS_RD_EN
always @(*)
`else
always @(posedge clk)
`endif
    rd_byte <= rd_bytes[rd_sel];


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        switch_fail <= 0;
        rd_sel <= 0;
        wr_sel <= 0;
        dirty <= 0;
    end
    else begin
        switch_fail <= 0;

`ifdef HAS_RD_EN
        rd_flags <= rd_en ? flags[rd_sel] : 8'dx;
`else
        rd_flags <= flags[rd_sel];
`endif

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

