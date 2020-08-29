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

module cdctl_i2c(
    input clk_i,
    output wire clk_o,

    input [1:0] addr_sel,

    inout sda,
    input scl,

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

wire [4:0] csr_address;
wire csr_read;
wire [7:0] csr_readdata;
wire csr_write;
wire [7:0] csr_writedata;

wire irq;
assign int_n = reset_n && irq ? 1'b0 : 1'bz;

i2c_slave i2c_slave_m(
    .clk(g_clk),
    .reset_n(reset_n),
    .chip_select(chip_select),
    
    .csr_address(csr_address),
    .csr_read(csr_read),
    .csr_readdata(csr_readdata),
    .csr_write(csr_write),
    .csr_writedata(csr_writedata),
    
    .addr_sel(addr_sel),
    
    .scl(scl),
    .sda(sda)
);

cdbus cdbus_m(
    .clk(g_clk),
    .reset_n(reset_n),
    .chip_select(chip_select),
    
    .csr_address(csr_address),
    .csr_read(csr_read),
    .csr_readdata(csr_readdata),
    .csr_write(csr_write),
    .csr_writedata(csr_writedata),
    
    .irq(irq),
    
    .rx(rx),
    .tx(tx),
    .tx_en(tx_en)
);

endmodule
