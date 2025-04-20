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
`ifdef CD_QSPI_ADVANCE
        input       advance, // sdo output advanced by 1/2 sck cycle
`endif

        output reg  [(A_WIDTH-1):0] csr_address,
        output      csr_read,
        input       [7:0] csr_readdata,
        output      csr_write,
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

reg [1:0] nss_d;
always @(posedge clk)
    nss_d <= {nss_d[0], nss};
assign chip_select = !nss_d[1];

wire spi_reset_n = reset_n && !nss;
reg  bit_cnt;
reg  [7:0] rreg;
reg  [7:0] treg;
reg  [1:0] byte_cnt;
reg  is_write;
reg  sdo_dat_en;

`ifdef CD_QSPI_ADVANCE
reg  sdo_dat_en_d;
reg  [3:0] treg74_d;
wire _sdo_en = advance ? sdo_dat_en : sdo_dat_en_d;
wire [3:0] _sdo = advance ? treg[7:4] : treg74_d;
`else
wire _sdo_en = sdo_dat_en;
wire [3:0] _sdo = treg[7:4];
`endif

`ifndef CD_SHARING_IO
    assign sdio = (spi_reset_n && _sdo_en) ? _sdo : 4'bz;
    wire [3:0] sdi = sdio;
`else
    assign sdo = _sdo;
    assign sdo_en = spi_reset_n && _sdo_en;
`endif

reg rw_det;
wire w_det_f = rw_det & is_write & byte_cnt[1];
wire r_det_f = (rw_det & !is_write) & byte_cnt[1];
reg  [2:0] event_wd;
reg  [2:0] event_rd;
assign csr_write = event_wd[2:1] == 2'b10;
assign csr_read = event_rd[2:1] == 2'b01;

reg [7:0] csr_writedata_d0;
reg [7:0] csr_writedata_d1;


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        event_rd <= 0;
        event_wd <= 0;
    end
    else begin
        event_wd <= {event_wd[1:0], w_det_f};
        event_rd <= {event_rd[1:0], r_det_f};
        csr_writedata_d1 <= csr_writedata_d0;
        csr_writedata <= csr_writedata_d1;
    end


// read from sdi
always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        bit_cnt <= 0;
        rreg <= 0;
        byte_cnt <= 0;
        is_write <= 0;
        rw_det <= 0;
    end
    else begin
        rreg <= {rreg[3:0], sdi};
        bit_cnt <= !bit_cnt;
        rw_det <= bit_cnt;

        if (bit_cnt) begin // rising edge of end of byte
            if (byte_cnt == 0) begin
                is_write <= rreg[3]; // MSB
                csr_address <= {rreg[(A_WIDTH-5):0], sdi};
            end
            if (byte_cnt != 2'd3)
                byte_cnt <= byte_cnt + 1'd1;
            
            csr_writedata_d0 <= {rreg[3:0], sdi};
        end
    end


// write to sdo
`ifndef CD_QSPI_ADVANCE

always @(negedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        treg <= 0;
        sdo_dat_en <= 0;
    end
    else begin
        if (!is_write && byte_cnt[1] && !bit_cnt)
            sdo_dat_en <= 1; // falling edge of the first byte's last bit

        if (!bit_cnt)
            treg <= csr_readdata;
        else
            treg <= {treg[3:0], 4'b0};
    end

`else

always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        treg <= 0;
        sdo_dat_en <= 0;
    end
    else begin
        if (!is_write && byte_cnt[0] && bit_cnt)
            sdo_dat_en <= 1; // rising edge of the first byte's last bit

        if (bit_cnt)
            treg <= csr_readdata;
        else
            treg <= {treg[3:0], 4'b0};
    end


always @(negedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        sdo_dat_en_d <= 0;
    end
    else begin
        sdo_dat_en_d <= sdo_dat_en;
        treg74_d <= treg[7:4];
    end
`endif


endmodule
