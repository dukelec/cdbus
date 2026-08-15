/*
 * This Source Code Form is subject to the terms of the CERN Open
 * Hardware Licence Version 2 - Strongly Reciprocal (CERN-OHL-S v2):
 * https://ohwr.org/cern_ohl_s_v2.txt (see the LICENSE file).
 * Notice: The CDBUS Exception (see the LICENSE_EXCEPTION file)
 * grants free commercial use in FPGAs and other programmable logic
 * devices; it does not extend to ASIC design or manufacturing.
 *
 * Copyright (c) 2017-2026 DUKELEC, All rights reserved.
 *
 * Author: Duke Fong <d@d-l.io>
 */

`define CD_CHIP_SELECT


module cdctl_spi(
    input       clk_i,
    output wire clk_o,

    input   sdi,
    output  sdo,
    input   sck,
    input   nss,

    input   rx,
    output  tx,
    output  tx_en,

    output  int_n
);

assign clk_o = ~clk_i;
wire clk = clk_o;
wire g_clk;
wire pll_lock;
wire chip_select;

reg rst_sim = 0;
always @(posedge clk)
    rst_sim = 1;

cdctl_pll b2v_pll_m(
    .REFERENCECLK(clk),
    .PLLOUTGLOBAL(g_clk),
    //.PLLOUTCORE(g_clk),
    .LOCK(pll_lock),
    .RESET(rst_sim));

// reset synchronizer: assert asynchronously, release synchronously
// init to 1 for simulation: create the initial falling edge of reset_n,
// as sub-module async resets are edge-sensitive in simulation
reg [1:0] reset_sync = 2'b11;
always @(posedge g_clk or negedge pll_lock)
    if (!pll_lock)
        reset_sync <= 0;
    else
        reset_sync <= {reset_sync[0], 1'b1};
wire reset_n = reset_sync[1];

wire [4:0] csr_address;
wire csr_read;
wire [7:0] csr_readdata;
wire csr_write;
wire [7:0] csr_writedata;

wire irq;
assign int_n = reset_n && irq ? 1'b0 : 1'bz;

spi_slave spi_slave_m(
    .clk(g_clk),
    .reset_n(reset_n),
    .chip_select(chip_select),
    .sdo_early(1'b0),
    
    .csr_address(csr_address),
    .csr_read(csr_read),
    .csr_readdata(csr_readdata),
    .csr_write(csr_write),
    .csr_writedata(csr_writedata),
    
    .sck(sck),
    .nss(nss),
    .sdi(sdi),
    .sdo(sdo)
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
