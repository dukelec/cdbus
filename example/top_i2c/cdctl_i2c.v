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
`define CD_CSR_CRC // remove it to leave out the crc mode


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

wire [5:0] csr_address;
wire csr_read;
wire [7:0] csr_readdata;
wire csr_write;
wire [7:0] csr_writedata;

wire core_read;
wire [7:0] core_readdata;
wire core_write;

wire crc_en;
wire sdo_early;
wire csr_cancel;

wire irq;
wire int_push_pull;
assign int_n = !reset_n ? 1'bz : int_push_pull ? !irq : (irq ? 1'b0 : 1'bz);

i2c_slave #(.A_WIDTH(6)) i2c_slave_m(
    .clk(g_clk),
    .reset_n(reset_n),
    .chip_select(chip_select),
    
    .crc_en(crc_en),
    .csr_cancel(csr_cancel),
    
    .csr_address(csr_address),
    .csr_read(csr_read),
    .csr_readdata(csr_readdata),
    .csr_write(csr_write),
    .csr_writedata(csr_writedata),
    
    .addr_sel(addr_sel),
    
    .scl(scl),
    .sda(sda)
);

cdctl_regs cdctl_regs_m(
    .clk(g_clk),
    .reset_n(reset_n),
    
    .csr_address(csr_address),
    .csr_read(csr_read),
    .csr_readdata(csr_readdata),
    .csr_write(csr_write),
    .csr_writedata(csr_writedata),
    
    .core_read(core_read),
    .core_readdata(core_readdata),
    .core_write(core_write),
    
    .int_push_pull(int_push_pull),
    .int_pull_up(),     // no such pad option and no re pin on this module
    .re_out_en(),
    .re_out(),
    .crc_en(crc_en),
    .sdo_early(sdo_early)
);

cdbus cdbus_m(
    .clk(g_clk),
    .reset_n(reset_n),
    .chip_select(chip_select),
`ifdef CD_CSR_CRC
    .csr_crc_en(crc_en),
    .csr_cancel(csr_cancel),
`endif
    
    .csr_address(csr_address[4:0]),
    .csr_read(core_read),
    .csr_readdata(core_readdata),
    .csr_write(core_write),
    .csr_writedata(csr_writedata),
    
    .irq(irq),
    
    .rx(rx),
    .tx(tx),
    .tx_en(tx_en)
);

endmodule
