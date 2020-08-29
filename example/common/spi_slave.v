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
        
        output reg  [(A_WIDTH-1):0] csr_address,
        output wire csr_read,
        input       [7:0] csr_readdata,
        output wire csr_write,
        output reg  [7:0] csr_writedata,
        
        input       sck,
        input       nss,
        input       sdi,
`ifndef SHARING_IO_PIN
        output      sdo
`else
        output      sdo,
        output      sdo_en
`endif
    );

reg [1:0] nss_d;
always @(posedge clk)
    nss_d <= {nss_d[0], nss};
assign chip_select = !nss_d[1];

wire spi_reset_n = reset_n && !nss;
reg  [2:0] bit_cnt;
reg  [7:0] rreg;
reg  [7:0] treg;
reg  is_first_byte;
reg  is_write;
reg  write_event;
reg  read_event;
reg  sdo_dat_en;

`ifndef SHARING_IO_PIN
    assign sdo = (spi_reset_n && sdo_dat_en) ? treg[7] : 1'bz;
`else
    assign sdo = treg[7];
    assign sdo_en = spi_reset_n && sdo_dat_en;
`endif

// read from sdi
always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        bit_cnt <= 0;
        rreg <= 0;
        is_first_byte <= 1;
        is_write <= 0;
        write_event <= 0;
        read_event <= 0;
    end
    else begin
        read_event <= 0;
        write_event <= 0;
        rreg <= {rreg[6:0], sdi};
        bit_cnt <= bit_cnt + 1'b1;
        
        if (bit_cnt == 6 && !is_first_byte && is_write) // avoid OP byte
            write_event <= 1;
        
        if (bit_cnt == 7) begin // first time at last bit posedge of first byte
            is_first_byte <= 0;
            csr_writedata <= {rreg[6:0], sdi};
            
            if (is_first_byte) begin
                is_write <= rreg[6]; // bit7
                csr_address <= {rreg[(A_WIDTH-2):0], sdi};
                
                read_event <= !rreg[6];
            end
            else if (!is_write) begin
                read_event <= 1;
            end
        end
    end

// write to sdo
always @(negedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        treg <= 0;
        sdo_dat_en <= 0;
    end
    else begin
        if (!is_write && !is_first_byte)
            sdo_dat_en <= 1;
        if (bit_cnt == 0)
            treg <= csr_readdata; // first time at last bit negedge of first byte
        else
            treg <= {treg[6:0], 1'b0};
    end


cdc_event cdc_write_m(
    .clk(sck),
    .reset_n(spi_reset_n),
    .src_event(write_event),
    
    .dst_clk(clk),
    .dst_reset_n(reset_n),
    .dst_event(csr_write)
);

cdc_event cdc_read_m(
    .clk(sck),
    .reset_n(spi_reset_n),
    .src_event(read_event),
    
    .dst_clk(clk),
    .dst_reset_n(reset_n),
    .dst_event(csr_read)
);

endmodule
