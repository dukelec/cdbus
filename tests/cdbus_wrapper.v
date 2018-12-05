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

`timescale 1 ns / 1 ps

module cdbus_wrapper(
        input       clk,
        input       reset_n,

        input       [3:0]   csr_address,
        input       [3:0]   csr_byteenable,
        input               csr_read,
        output      [31:0]  csr_readdata,
        input               csr_write,
        input       [31:0]  csr_writedata,
        
        input       [5:0]   rx_mm_address,
        input       [3:0]   rx_mm_byteenable,
        input               rx_mm_read,
        output      [31:0]  rx_mm_readdata,
        input               rx_mm_write,
        input       [31:0]  rx_mm_writedata,
        
        input       [5:0]   tx_mm_address,
        input       [3:0]   tx_mm_byteenable,
        input               tx_mm_read,
        output      [31:0]  tx_mm_readdata,
        input               tx_mm_write,
        input       [31:0]  tx_mm_writedata,

        output      irq,

        inout       bus_a
    );

wire tx;
wire tx_en;
wire rx = tx_en ? tx : (bus_a !== 0);
assign bus_a = tx_en ? tx : 1'bz;

cdbus cdbus_m(
          .clk(clk),
          .reset_n(reset_n),
          .irq(irq),
          
          .csr_address(csr_address),
          .csr_byteenable(csr_byteenable),
          .csr_read(csr_read),
          .csr_readdata(csr_readdata),
          .csr_write(csr_write),
          .csr_writedata(csr_writedata),
          
          .rx_mm_address(rx_mm_address),
          .rx_mm_byteenable(rx_mm_byteenable),
          .rx_mm_read(rx_mm_read),
          .rx_mm_readdata(rx_mm_readdata),
          .rx_mm_write(rx_mm_write),
          .rx_mm_writedata(rx_mm_writedata),
          
          .tx_mm_address(tx_mm_address),
          .tx_mm_byteenable(tx_mm_byteenable),
          .tx_mm_read(tx_mm_read),
          .tx_mm_readdata(tx_mm_readdata),
          .tx_mm_write(tx_mm_write),
          .tx_mm_writedata(tx_mm_writedata),
          
          .rx(rx),
          .tx(tx),
          .tx_en(tx_en)
      );

initial begin
    $dumpfile("cdbus.vcd");
    $dumpvars();
end

endmodule
