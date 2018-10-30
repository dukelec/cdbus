/*
 * This Source Code Form is subject to the terms of the Mozilla
 * Public License, v. 2.0. If a copy of the MPL was not distributed
 * with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
 * Notice: The scope granted to MPL excludes the ASIC industry.
 *
 * Copyright (c) 2017 DUKELEC, All rights reserved.
 *
 * Author: Duke Fong <duke@dukelec.com>
 */

module pp_ram
       #(
           parameter A_WIDTH = 8,
           parameter N_WIDTH = 1
       )(
           input                 clk,
           input                 reset_n,

           output reg   [7:0]    rd_byte,
           input [(A_WIDTH-1):0] rd_addr,
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

reg [7:0] ram[2**N_WIDTH-1:0][2**A_WIDTH-1:0];
reg [7:0] flags[2**N_WIDTH-1:0];

reg [N_WIDTH-1:0] wr_sel;
reg [N_WIDTH-1:0] rd_sel;
reg [2**N_WIDTH-1:0] dirty;

assign unread = (dirty != 0);


always @(posedge clk) begin

    if (wr_sel != rd_sel) begin
        rd_byte <= ram[rd_sel][rd_addr];
        rd_flags <= flags[rd_sel];
    end
    else begin // no need to read when writing data
        rd_byte <= 0;
        rd_flags <= 0;
    end

    if (wr_en) begin
        ram[wr_sel][wr_addr] <= wr_byte;
    end
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

