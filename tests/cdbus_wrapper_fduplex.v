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

`timescale 1 ns / 1 ps

module cdbus_wrapper_fduplex(
        input       clk0,
        input       clk1,
        input       clk2,
        input       reset0,
        input       reset1,
        input       reset2,

        input       [4:0] csr_addr0,
        input       csr_read0,
        output      [7:0] csr_rdata0,
        input       csr_write0,
        input       [7:0] csr_wdata0,

        input       [4:0] csr_addr1,
        input       csr_read1,
        output      [7:0] csr_rdata1,
        input       csr_write1,
        input       [7:0] csr_wdata1,

        input       [4:0] csr_addr2,
        input       csr_read2,
        output      [7:0] csr_rdata2,
        input       csr_write2,
        input       [7:0] csr_wdata2,

        output      irq0,
        output      irq1,
        output      irq2,

        inout       bus_a,

        input       dbg0,
        input       dbg1
    );

wire tx0;
wire tx1;
wire tx2;
wire tx_en0;
wire tx_en1;
wire tx_en2;

wire rx0 = tx1;
wire rx1 = tx0;

cdbus cdbus_m0(
          .clk(clk0),
          .reset_n(reset0),
          .chip_select(1'b1),
          .irq(irq0),
          
          .csr_address(csr_addr0),
          .csr_read(csr_read0),
          .csr_readdata(csr_rdata0),
          .csr_write(csr_write0),
          .csr_writedata(csr_wdata0),
          
          .rx(rx0),
          .tx(tx0),
          .tx_en(tx_en0)
      );

cdbus cdbus_m1(
          .clk(clk1),
          .reset_n(reset1),
          .chip_select(1'b1),
          .irq(irq1),
          
          .csr_address(csr_addr1),
          .csr_read(csr_read1),
          .csr_readdata(csr_rdata1),
          .csr_write(csr_write1),
          .csr_writedata(csr_wdata1),
          
          .rx(rx1),
          .tx(tx1),
          .tx_en(tx_en1)
      );

initial begin
    $dumpfile("cdbus.vcd");
    $dumpvars();
end

endmodule
