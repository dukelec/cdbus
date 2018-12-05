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

module cd_ram
       #(
           parameter A_WIDTH = 6,
           parameter N_WIDTH = 1,
           parameter MM4RD = 1
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

reg [7:0] ram0[2**N_WIDTH-1:0][2**A_WIDTH-1:0];
reg [7:0] ram1[2**N_WIDTH-1:0][2**A_WIDTH-1:0];
reg [7:0] ram2[2**N_WIDTH-1:0][2**A_WIDTH-1:0];
reg [7:0] ram3[2**N_WIDTH-1:0][2**A_WIDTH-1:0];
reg [7:0] flags[2**N_WIDTH-1:0];

reg [N_WIDTH-1:0] wr_sel;
reg [N_WIDTH-1:0] rd_sel;
reg [2**N_WIDTH-1:0] dirty;
wire [N_WIDTH-1:0] mm_sel = MM4RD ? rd_sel : wr_sel;

assign unread = (dirty != 0);


always @(posedge clk) begin

    if (rd_en) begin
        if (rd_addr[1:0] == 2'b00)
            rd_byte <= ram0[rd_sel][rd_addr[(A_WIDTH+1):2]];
        else if (rd_addr[1:0] == 2'b01)
            rd_byte <= ram1[rd_sel][rd_addr[(A_WIDTH+1):2]];
        else if (rd_addr[1:0] == 2'b10)
            rd_byte <= ram2[rd_sel][rd_addr[(A_WIDTH+1):2]];
        else if (rd_addr[1:0] == 2'b11)
            rd_byte <= ram3[rd_sel][rd_addr[(A_WIDTH+1):2]];
        
        rd_flags <= flags[rd_sel];
    end

    if (mm_read)
        mm_readdata <= {ram3[mm_sel][mm_address],
                        ram2[mm_sel][mm_address],
                        ram1[mm_sel][mm_address],
                        ram0[mm_sel][mm_address]};

    if (MM4RD) begin
        if (wr_en) begin
            if (wr_addr[1:0] == 2'b00)
                ram0[wr_sel][wr_addr[(A_WIDTH+1):2]] <= wr_byte;
            else if (wr_addr[1:0] == 2'b01)
                ram1[wr_sel][wr_addr[(A_WIDTH+1):2]] <= wr_byte;
            else if (wr_addr[1:0] == 2'b10)
                ram2[wr_sel][wr_addr[(A_WIDTH+1):2]] <= wr_byte;
            else if (wr_addr[1:0] == 2'b11)
                ram3[wr_sel][wr_addr[(A_WIDTH+1):2]] <= wr_byte;
        end
    end
    else begin
        if (mm_write) begin
            if (mm_byteenable[0])
                ram0[mm_sel][mm_address] <= mm_writedata[7:0];
            if (mm_byteenable[1])
                ram1[mm_sel][mm_address] <= mm_writedata[15:8];
            if (mm_byteenable[2])
                ram2[mm_sel][mm_address] <= mm_writedata[23:16];
            if (mm_byteenable[3])
                ram3[mm_sel][mm_address] <= mm_writedata[31:24];
        end
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

