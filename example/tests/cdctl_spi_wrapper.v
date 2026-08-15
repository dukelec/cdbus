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

`timescale 1 ns / 1 ps

module cdctl_spi_wrapper(
        input       clk,

        input       sdi,
        inout       sdo,
        input       sck,
        input       nss,

        output      int_n,

        inout       bus_a
    );

wire tx;
wire tx_en;
wire rx = tx_en ? tx : (bus_a !== 0);
assign bus_a = tx_en ? tx : 1'bz;

cdctl_spi cdctl_spi_m(
          .clk_i(clk),
          
          .sdi(sdi),
          .sdo(sdo),
          .sck(sck),
          .nss(nss),
          
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
