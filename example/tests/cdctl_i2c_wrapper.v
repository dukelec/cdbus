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

module cdctl_i2c_wrapper(
        input       clk,

        input       sda_m, // open-drain drive from master: 0: pull low, 1: release
        output      sda,   // resolved bus level with pull-up
        input       scl,

        output      int_n,

        inout       bus_a
    );

wire sda_bus;
assign sda_bus = sda_m ? 1'bz : 1'b0;
assign sda = (sda_bus !== 1'b0);

wire tx;
wire tx_en;
wire rx = tx_en ? tx : (bus_a !== 0);
assign bus_a = tx_en ? tx : 1'bz;

cdctl_i2c cdctl_i2c_m(
          .clk_i(clk),

          .addr_sel(2'b00),

          .sda(sda_bus),
          .scl(scl),

          .int_n(int_n),

          .rx(rx),
          .tx(tx),
          .tx_en(tx_en)
      );

initial begin
    $dumpfile("cdctl.vcd");
    $dumpvars();
end

endmodule
