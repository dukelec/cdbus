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

module spi_slave
    #(
        parameter A_WIDTH = 5
    )(
        input       clk,
        input       reset_n,
        output      chip_select,
        input       sdo_early, // output sdo 1/2 sck cycle early

        output reg  [(A_WIDTH-1):0] csr_address,
        output      csr_read,
        input       [7:0] csr_readdata,
        output      csr_write,
        output reg  [7:0] csr_writedata,

        input       sck,
        input       nss,
        input       sdi,
`ifndef CD_SHARING_IO
        output      sdo
`else
        output      sdo,
        output      sdo_en
`endif
    );

reg [2:0] nss_d;
always @(posedge clk)
    nss_d <= {nss_d[1:0], nss};
assign chip_select = !nss_d[2];

wire spi_reset_n = reset_n && !nss;
reg  [2:0] bit_cnt;
reg  [6:0] rreg;
reg  [7:0] treg;
reg  is_first_byte;
reg  is_first_byte_d;
reg  is_write;
reg  sdo_dat_en;
reg  sdo_dat_en_d;
reg  treg7_d;

wire _sdo_en = sdo_early ? sdo_dat_en : sdo_dat_en_d;
wire _sdo = sdo_early ? treg[7] : treg7_d;

`ifndef CD_SHARING_IO
    assign sdo = (spi_reset_n && _sdo_en) ? _sdo : 1'bz;
`else
    assign sdo = _sdo;
    assign sdo_en = spi_reset_n && _sdo_en;
`endif

reg  w_tog; // toggle once per event, immune to pulse-width loss across domains
reg  r_tog;
reg  [2:0] event_wd;
reg  [2:0] event_rd;
assign csr_write = event_wd[2] ^ event_wd[1];
assign csr_read = event_rd[2] ^ event_rd[1];

// toggles must survive the end of transfer, do not reset with spi_reset_n,
// otherwise the clk domain would take the async clear as an extra event
always @(posedge sck or negedge reset_n)
    if (!reset_n) begin
        w_tog <= 0;
        r_tog <= 0;
    end
    else if (!is_first_byte_d) begin
        if (is_write) begin
            if (bit_cnt == 7) // rising edge of the last bit of each data byte
                w_tog <= !w_tog;
        end
        else begin
            if (bit_cnt == 0) // rising edge of bit 1 of each data byte
                r_tog <= !r_tog;
        end
    end


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        event_wd <= 0;
        event_rd <= 0;
    end
    else begin
        event_wd <= {event_wd[1:0], w_tog};
        event_rd <= {event_rd[1:0], r_tog};
    end


// read from sdi
always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        bit_cnt <= 0;
        rreg <= 0;
        is_first_byte <= 1;
        is_first_byte_d <= 1;
        is_write <= 0;
    end
    else begin
        rreg <= {rreg[5:0], sdi};
        bit_cnt <= bit_cnt + 1'b1;
        is_first_byte_d <= is_first_byte;

        if (bit_cnt == 6) begin // rising edge of penultimate bit
            if (is_first_byte) begin
                is_write <= rreg[5]; // MSB
                csr_address <= {rreg[(A_WIDTH-2):0], sdi};
            end
            is_first_byte <= 0;
        end

        if (bit_cnt == 7) // rising edge of last bit
            csr_writedata <= {rreg, sdi};
    end


// write to sdo
always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        treg <= 0;
        sdo_dat_en <= 0;
    end
    else begin
        if (!is_write && !is_first_byte)
            sdo_dat_en <= 1; // rising edge of the first byte's last bit

        if (bit_cnt == 7)
            treg <= csr_readdata;
        else
            treg <= {treg[6:0], 1'b0};
    end


always @(negedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        sdo_dat_en_d <= 0;
    end
    else begin
        sdo_dat_en_d <= sdo_dat_en;
        treg7_d <= treg[7];
    end


endmodule
