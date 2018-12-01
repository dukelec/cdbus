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

        input       [4:0] csr_address,
        input       csr_read,
        output      [7:0] csr_readdata,
        input       csr_write,
        input       [7:0] csr_writedata,

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
          .chip_select(1'b1),
          .irq(irq),
          
          .csr_address(csr_address),
          .csr_read(csr_read),
          .csr_readdata(csr_readdata),
          .csr_write(csr_write),
          .csr_writedata(csr_writedata),
          
          .rx(rx),
          .tx(tx),
          .tx_en(tx_en)
      );

initial begin
    $dumpfile("cdbus.vcd");
    $dumpvars();
end

endmodule
