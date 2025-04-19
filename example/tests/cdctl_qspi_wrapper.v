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

module cdctl_qspi_wrapper(
        input       clk,

        inout [3:0] sdio,
        input       sck,
        input       nss,

        output      int_n,

        inout       bus_a
    );

wire tx;
wire tx_en;
wire rx = tx_en ? tx : (bus_a !== 0);
assign bus_a = tx_en ? tx : 1'bz;

cdctl_qspi cdctl_qspi_m(
          .clk_i(clk),
          
          .sdio(sdio),
          .sck(sck),
          .nss(nss),
          
          .int_n(int_n),
          
          .rx(rx),
          .tx(tx),
          .tx_en(tx_en)
      );

initial begin
    $dumpfile("cdctl_qspi.vcd");
    $dumpvars();
end

endmodule
