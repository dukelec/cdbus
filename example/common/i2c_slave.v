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

module i2c_slave
    #(
        parameter A_WIDTH = 5
    )(
        input clk,
        input reset_n,
        output reg chip_select,
        
        output reg [(A_WIDTH-1):0] csr_address,
        output reg csr_read,
        input      [7:0] csr_readdata,
        output reg csr_write,
        output reg [7:0] csr_writedata,

`ifndef SHARING_IO_PIN
        input [2:0] addr_sel,
        inout sda,
`else
        input [1:0] addr_sel,
        input sda_in,
        output reg sda_out,
        output sda_en,
`endif
        input scl
    );

`ifndef SHARING_IO_PIN
    reg sda_out;
    assign sda = (reset_n & ~sda_out) ? 1'b0 : 1'bz;
    assign sda_in = (sda !== 1'b0);
`else
    assign sda_en = reset_n & ~sda_out;
`endif

wire [6:0] dev_addr = {4'b1100, 1'b0, addr_sel[1:0]};

reg  [2:0] scl_r;
always @(posedge clk)
    scl_r <= {scl_r[1:0], scl};

reg  [2:0] sda_in_r;
wire sda_in_d = sda_in_r[1];
always @(posedge clk)
    sda_in_r <= {sda_in_r[1:0], sda_out ? (sda_in !== 1'b0) : 1'b1};

wire scl_rising = (scl_r[2:1] == 2'b01);  // detect scl rising edges
wire scl_falling = (scl_r[2:1] == 2'b10); // detect scl falling edges

wire start = (sda_in_r[2:1] == 2'b10 && scl_r[1] == 1'b1);
wire stop = (sda_in_r[2:1] == 2'b01 && scl_r[1] == 1'b1);


reg  [3:0] bit_cnt;
reg  ack;
reg  [7:0] rreg;
reg  is_addr_byte;
reg  is_skip;
reg  is_write;
reg  is_cmd_byte;
reg  [7:0] c_readdata; // speed up

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        chip_select <= 0;
        //rreg <= 0;
        //csr_address <= 0;
        csr_read <= 0;
        csr_write <= 0;
        //csr_writedata <= 0;
        bit_cnt <= 4'b1111;
        ack <= 0;
        is_addr_byte <= 1;
        is_skip <= 0;
        is_write <= 1;
        is_cmd_byte <= 1;
        sda_out <= 1;
    end
    else begin
        csr_read <= 0;
        csr_write <= 0;
        c_readdata <= csr_readdata;
        
        if (start)
            chip_select <= 1;
        if (stop)
            chip_select <= 0;
        
        if (start || stop) begin
            bit_cnt <= 4'b1111;
            ack <= 0;
            is_addr_byte <= 1;
            is_skip <= 0;
            is_write <= 1;
            is_cmd_byte <= 1;
            sda_out <= 1;
        end
        else if (!is_skip) begin
        
            if (scl_rising) begin
                rreg <= {rreg[6:0], sda_in_d};
            
                if (bit_cnt == 7) begin // first time at last bit posedge of first byte
                    csr_writedata <= {rreg[6:0], sda_in_d};
                    
                    if (is_addr_byte) begin
                        is_write <= !sda_in_d;
                        is_skip <= rreg[6:0] != dev_addr;
                        ack <= 1;
                    end
                    else if (is_write) begin
                        is_cmd_byte <= 0;
                        ack <= 1;
                        if (is_cmd_byte)
                            csr_address <= {rreg[(A_WIDTH-2):0], sda_in_d};
                        else
                            csr_write <= 1;
                    end
                end
                else if (bit_cnt == 8) begin
                    if (!ack && sda_in_d)
                        is_skip <= 1;
                    if (is_addr_byte)
                        is_addr_byte <= 0;
                    else if (!is_write)
                        csr_read <= 1;
                end
            end
            else if (scl_falling) begin
                bit_cnt <= bit_cnt + 1'b1;
                
                if (is_write) begin
                    sda_out <= 1;
                end
                else begin
                    case (bit_cnt)
                        8: sda_out <= c_readdata[7];
                        0: sda_out <= c_readdata[6];
                        1: sda_out <= c_readdata[5];
                        2: sda_out <= c_readdata[4];
                        3: sda_out <= c_readdata[3];
                        4: sda_out <= c_readdata[2];
                        5: sda_out <= c_readdata[1];
                        6: sda_out <= c_readdata[0];
                    endcase
                end
                
                if (bit_cnt == 7) begin
                    if (ack)
                        sda_out <= 0;
                    else
                        sda_out <= 1;
                end
                else if (bit_cnt == 8) begin
                    bit_cnt <= 0;
                    if (ack)
                        ack <= 0;
                end
            end
        end
    end


endmodule
