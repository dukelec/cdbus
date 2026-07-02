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

module qspi_slave
    #(
        parameter A_WIDTH = 5
    )(
        input       clk,
        input       reset_n,
        output      chip_select,
        input       advance, // sdo output advanced by 1/2 sck cycle

        output reg  [(A_WIDTH-1):0] csr_address,
        output      csr_read,
        input       [7:0] csr_readdata,
        output reg  csr_write,
        output reg  [7:0] csr_writedata,

        input       sck,
        input       nss,
`ifndef CD_SHARING_IO
        inout       [3:0] sdio
`else
        input       [3:0] sdi,
        output      [3:0] sdo,
        output      sdo_en
`endif
    );

reg [3:0] nss_d;
always @(posedge clk)
    nss_d <= {nss_d[2:0], nss};
assign chip_select = !nss_d[3] || !nss_d[2];

wire spi_reset_n = reset_n && !nss;
reg  bit_cnt;
reg  [7:0] rreg;
reg  [7:0] treg;
reg  [1:0] byte_cnt;
reg  is_write;
reg  sdo_dat_en;
reg  sdo_dat_en_d;
reg  [3:0] treg74_d;

wire _sdo_en = advance ? sdo_dat_en : sdo_dat_en_d;
wire [3:0] _sdo = advance ? treg[7:4] : treg74_d;

`ifndef CD_SHARING_IO
    assign sdio = (spi_reset_n && _sdo_en) ? _sdo : 4'bz;
    wire [3:0] sdi = sdio;
`else
    assign sdo = _sdo;
    assign sdo_en = spi_reset_n && _sdo_en;
`endif

reg  w_tog; // toggle once per event, immune to pulse-width loss across domains
reg  r_tog;
reg  [2:0] event_wd;
reg  [2:0] event_rd;
wire csr_write_ = event_wd[2] ^ event_wd[1];
assign csr_read = event_rd[2] ^ event_rd[1];

reg [7:0] csr_writedata_d0;
reg [7:0] csr_writedata_d1;

reg [7:0] ram[1:0]; // FIFO
reg ra;
reg wa;

always @(posedge clk) begin
    if (!chip_select) begin
        wa <= 0;
    end
    else if (csr_read) begin
        ram[wa] <= csr_readdata;
        wa <= !wa;
    end
end


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        event_rd <= 0;
        event_wd <= 0;
        csr_write <= 0;
    end
    else begin
        event_wd <= {event_wd[1:0], w_tog};
        event_rd <= {event_rd[1:0], r_tog};
        csr_writedata_d1 <= csr_writedata_d0;
        csr_writedata <= csr_writedata_d1;
        csr_write <= csr_write_; // wait for csr_writedata stable
    end


// read from sdi
always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        bit_cnt <= 0;
        rreg <= 0;
        byte_cnt <= 0;
        is_write <= 0;
    end
    else begin
        rreg <= {rreg[3:0], sdi};
        bit_cnt <= !bit_cnt;

        if (bit_cnt) begin // rising edge of end of byte
            if (byte_cnt == 0)
                csr_address <= {rreg[(A_WIDTH-5):0], sdi};
            if (byte_cnt != 2'd3)
                byte_cnt <= byte_cnt + 1'd1;

            csr_writedata_d0 <= {rreg[3:0], sdi};
        end
        else if (byte_cnt == 0) begin
            is_write <= sdi[3]; // MSB, captured half byte early
        end
    end


// toggles must survive the end of transfer, do not reset with spi_reset_n,
// otherwise the clk domain would take the async clear as an extra event
always @(posedge sck or negedge reset_n)
    if (!reset_n) begin
        w_tog <= 0;
        r_tog <= 0;
    end
    else if (bit_cnt) begin // rising edge of end of byte
        if (!is_write)
            r_tog <= !r_tog;
        else if (byte_cnt != 0)
            w_tog <= !w_tog;
    end


// write to sdo

always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        treg <= 0;
        sdo_dat_en <= 0;
        ra <= 0;
    end
    else begin
        if (!is_write && byte_cnt[1] && bit_cnt)
            sdo_dat_en <= 1; // rising edge of the first byte's last bit

        if (bit_cnt && byte_cnt[1]) begin
            treg <= ram[ra];
            ra <= !ra;
        end
        else begin
            treg <= {treg[3:0], 4'b0};
        end
    end


always @(negedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        sdo_dat_en_d <= 0;
    end
    else begin
        sdo_dat_en_d <= sdo_dat_en;
        treg74_d <= treg[7:4];
    end


endmodule
