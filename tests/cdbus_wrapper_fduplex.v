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


        input       [3:0]   csr_addr0,
        input       [3:0]   csr_byteenable0,
        input               csr_read0,
        output      [31:0]  csr_rdata0,
        input               csr_write0,
        input       [31:0]  csr_wdata0,
        
        input       [5:0]   rx_mm_address0,
        input       [3:0]   rx_mm_byteenable0,
        input               rx_mm_read0,
        output      [31:0]  rx_mm_readdata0,
        input               rx_mm_write0,
        input       [31:0]  rx_mm_writedata0,
        
        input       [5:0]   tx_mm_address0,
        input       [3:0]   tx_mm_byteenable0,
        input               tx_mm_read0,
        output      [31:0]  tx_mm_readdata0,
        input               tx_mm_write0,
        input       [31:0]  tx_mm_writedata0,
        

        input       [3:0]   csr_addr1,
        input       [3:0]   csr_byteenable1,
        input               csr_read1,
        output      [31:0]  csr_rdata1,
        input               csr_write1,
        input       [31:0]  csr_wdata1,
        
        input       [5:0]   rx_mm_address1,
        input       [3:0]   rx_mm_byteenable1,
        input               rx_mm_read1,
        output      [31:0]  rx_mm_readdata1,
        input               rx_mm_write1,
        input       [31:0]  rx_mm_writedata1,
        
        input       [5:0]   tx_mm_address1,
        input       [3:0]   tx_mm_byteenable1,
        input               tx_mm_read1,
        output      [31:0]  tx_mm_readdata1,
        input               tx_mm_write1,
        input       [31:0]  tx_mm_writedata1,


        input       [3:0]   csr_addr2,
        input       [3:0]   csr_byteenable2,
        input               csr_read2,
        output      [31:0]  csr_rdata2,
        input               csr_write2,
        input       [31:0]  csr_wdata2,
        
        input       [5:0]   rx_mm_address2,
        input       [3:0]   rx_mm_byteenable2,
        input               rx_mm_read2,
        output      [31:0]  rx_mm_readdata2,
        input               rx_mm_write2,
        input       [31:0]  rx_mm_writedata2,
        
        input       [5:0]   tx_mm_address2,
        input       [3:0]   tx_mm_byteenable2,
        input               tx_mm_read2,
        output      [31:0]  tx_mm_readdata2,
        input               tx_mm_write2,
        input       [31:0]  tx_mm_writedata2,
        
        
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
          .irq(irq0),
          
          .csr_address(csr_addr0),
          .csr_byteenable(csr_byteenable0),
          .csr_read(csr_read0),
          .csr_readdata(csr_rdata0),
          .csr_write(csr_write0),
          .csr_writedata(csr_wdata0),
          
          .rx_mm_address(rx_mm_address0),
          .rx_mm_byteenable(rx_mm_byteenable0),
          .rx_mm_read(rx_mm_read0),
          .rx_mm_readdata(rx_mm_readdata0),
          .rx_mm_write(rx_mm_write0),
          .rx_mm_writedata(rx_mm_writedata0),
          
          .tx_mm_address(tx_mm_address0),
          .tx_mm_byteenable(tx_mm_byteenable0),
          .tx_mm_read(tx_mm_read0),
          .tx_mm_readdata(tx_mm_readdata0),
          .tx_mm_write(tx_mm_write0),
          .tx_mm_writedata(tx_mm_writedata0),
          
          .rx(rx0),
          .tx(tx0),
          .tx_en(tx_en0)
      );

cdbus cdbus_m1(
          .clk(clk1),
          .reset_n(reset1),
          .irq(irq1),
          
          .csr_address(csr_addr1),
          .csr_byteenable(csr_byteenable1),
          .csr_read(csr_read1),
          .csr_readdata(csr_rdata1),
          .csr_write(csr_write1),
          .csr_writedata(csr_wdata1),
          
          .rx_mm_address(rx_mm_address1),
          .rx_mm_byteenable(rx_mm_byteenable1),
          .rx_mm_read(rx_mm_read1),
          .rx_mm_readdata(rx_mm_readdata1),
          .rx_mm_write(rx_mm_write1),
          .rx_mm_writedata(rx_mm_writedata1),
          
          .tx_mm_address(tx_mm_address1),
          .tx_mm_byteenable(tx_mm_byteenable1),
          .tx_mm_read(tx_mm_read1),
          .tx_mm_readdata(tx_mm_readdata1),
          .tx_mm_write(tx_mm_write1),
          .tx_mm_writedata(tx_mm_writedata1),
          
          .rx(rx1),
          .tx(tx1),
          .tx_en(tx_en1)
      );

initial begin
    $dumpfile("cdbus.vcd");
    $dumpvars();
end

endmodule
