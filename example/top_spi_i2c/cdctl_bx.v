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

`define SHARING_IO_PIN

module cdctl_bx(
    input clk_i,
    output wire clk_o,

    input intf_sel,
    input [1:0] addr_sel,

    input sdi,
    inout sdo_sda,
    input sck_scl,
    input nss,

    input rx,
    output tx,
    output tx_en,

    output int_n
);

assign clk_o = ~clk_i;
wire clk = clk_o;

reg rst_sim = 0;
always @(posedge clk)
    rst_sim = 1;

cdctl_pll b2v_pll_m(
    .REFERENCECLK(clk),
    .PLLOUTGLOBAL(g_clk),
    //.PLLOUTCORE(g_clk),
    .LOCK(reset_n),
    .RESET(rst_sim));

wire [4:0] spi_address;
wire spi_read;
wire spi_write;
wire [7:0] spi_writedata;

wire [4:0] i2c_address;
wire i2c_read;
wire i2c_write;
wire [7:0] i2c_writedata;

wire [7:0] csr_readdata;

wire irq;
assign int_n = reset_n && irq ? 1'b0 : 1'bz;

wire sdo;
wire sdo_en;
wire sda_out;
wire sda_en;
assign sdo_sda = intf_sel ? (sdo_en ? sdo : 1'bz) : (sda_en ? sda_out : 1'bz);


i2c_slave i2c_slave_m(
    .clk(g_clk),
    .reset_n(reset_n),
    
    .csr_address(i2c_address),
    .csr_read(i2c_read),
    .csr_readdata(csr_readdata),
    .csr_write(i2c_write),
    .csr_writedata(i2c_writedata),
    
    .addr_sel(addr_sel),
    
    .scl(intf_sel ? 1'b1 : sck_scl),
    .sda_in(intf_sel ? 1'b1 : (sdo_sda !== 1'b0)),
    .sda_out(sda_out),
    .sda_en(sda_en)
);

spi_slave spi_slave_m(
    .clk(g_clk),
    .reset_n(reset_n),
    
    .csr_address(spi_address),
    .csr_read(spi_read),
    .csr_readdata(csr_readdata),
    .csr_write(spi_write),
    .csr_writedata(spi_writedata),
    
    .sck(intf_sel ? sck_scl : 1'b1),
    .nss(intf_sel ? nss : 1'b1),
    .sdi(sdi),
    .sdo(sdo),
    .sdo_en(sdo_en)
);

cdbus cdbus_m(
    .clk(g_clk),
    .reset_n(reset_n),
    .chip_select(1'b1),
    
    .csr_address(intf_sel ? spi_address : i2c_address),
    .csr_read(intf_sel ? spi_read : i2c_read),
    .csr_readdata(csr_readdata),
    .csr_write(intf_sel ? spi_write : i2c_write),
    .csr_writedata(intf_sel ? spi_writedata : i2c_writedata),
    
    .irq(irq),
    
    .rx(rx),
    .tx(tx),
    .tx_en(tx_en)
);

endmodule
