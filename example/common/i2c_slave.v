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

module i2c_slave
    #(
        parameter A_WIDTH = 5,
        parameter DAT_ADDR = 'h15,  // crc mode: the two addresses written byte by byte,
        parameter HOLD_ADDR = 'h17  // any other address takes one byte after the crc check
    )(
        input clk,
        input reset_n,
        output reg chip_select,

        input crc_en,       // crc mode
        output csr_cancel,  // crc mode: no valid write in this transfer

        output reg [(A_WIDTH-1):0] csr_address,
        output reg csr_read,
        input      [7:0] csr_readdata,
        output reg csr_write,
        output reg [7:0] csr_writedata,

`ifndef CD_SHARING_IO
        input [1:0] addr_sel,
        inout sda,
`else
        input [1:0] addr_sel,
        input sda_in,
        output reg sda_out,
        output sda_en,
`endif
        input scl
    );

// crc mode, crc16 (ccitt-false, msb first) over all the bytes since the first start:
//   write: dev_w, addr, n-1, n data bytes, crc16
//   read:  dev_w, addr, n-1, restart, dev_r, write status, n data bytes, crc16
localparam
    PH_CMD  = 3'd0, // register address
    PH_LEN  = 3'd1,
    PH_DAT  = 3'd2, // the only phase after cmd without crc mode
    PH_CRC0 = 3'd3,
    PH_CRC1 = 3'd4,
    PH_END  = 3'd5,
    PH_STAT = 3'd6; // first byte of a read

`ifndef CD_SHARING_IO
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
reg  [7:0] c_readdata; // speed up

reg  [2:0] ph;
reg  crc_on;
reg  [7:0] len;     // data bytes left after the current one
reg  len_err;       // more than one byte for an address which takes only one
reg  has_data;      // crc mode: data written in this transfer, nothing is taken after it
reg  [15:0] crc;
reg  wr_tog;        // toggle once per accepted write of crc mode, reported by the next read
reg  xfer_bad;
assign csr_cancel = xfer_bad;

wire [7:0] rbyte = {rreg[6:0], sda_in_d};
wire is_burst = (csr_address == DAT_ADDR) || (csr_address == HOLD_ADDR);

wire [7:0] tbyte = (!crc_on || ph == PH_DAT) ? c_readdata :
                   (ph == PH_STAT) ? (wr_tog ? 8'h0f : 8'hf0) :
                   (ph == PH_CRC0) ? crc[15:8] :
                   (ph == PH_CRC1) ? crc[7:0] : 8'hff;

function [15:0] crc_byte(input [15:0] c, input [7:0] d);
    integer i;
    begin
        crc_byte = c;
        for (i = 7; i >= 0; i = i - 1)
            crc_byte = {crc_byte[14:0], 1'b0} ^ ({16{crc_byte[15] ^ d[i]}} & 16'h1021);
    end
endfunction

// updated per byte: the scl pulse before a repeated start looks like one more bit
wire rd_dat = !is_write && !is_addr_byte; // bytes sent by the device
wire crc_hold = rd_dat && (ph == PH_CRC0 || ph == PH_CRC1 || ph == PH_END);
wire [15:0] crc_nxt = crc_byte(crc, rd_dat ? tbyte : rbyte);
wire crc_pass = (crc_nxt == 0) && !len_err; // at the last bit of a write

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
        sda_out <= 1;
        ph <= PH_CMD;
        crc_on <= 0;
        len <= 0;
        len_err <= 0;
        has_data <= 0;
        crc <= 16'hffff;
        wr_tog <= 0;
        xfer_bad <= 0;
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
            ph <= PH_CMD;
            sda_out <= 1;
            
            if (start && !chip_select) begin // not a repeated start
                crc_on <= crc_en;
                xfer_bad <= crc_en;
                has_data <= 0;
                crc <= 16'hffff;
            end
            else if (start && has_data) begin
                is_skip <= 1;
            end
        end
        else if (!is_skip) begin
        
            if (scl_rising) begin
                rreg <= {rreg[6:0], sda_in_d};
                
                if (bit_cnt == 7) begin // first time at last bit posedge of first byte
                    if (!crc_hold)
                        crc <= crc_nxt;
                    
                    if (is_addr_byte) begin
                        is_write <= !sda_in_d;
                        ack <= 1;
                        if (sda_in_d)
                            ph <= PH_STAT;
                        if (rreg[6:0] != dev_addr) begin
                            is_skip <= 1;
                            // release chip_select during other devices' transactions,
                            // keep int_flag snapshot fresh for repeated start
                            chip_select <= 0;
                        end
                    end
                    else if (is_write) begin
                        ack <= 1;
                        case (ph)
                            PH_CMD: begin
                                csr_address <= {rreg[(A_WIDTH-2):0], sda_in_d};
                                ph <= crc_on ? PH_LEN : PH_DAT;
                            end
                            PH_LEN: begin
                                ph <= PH_DAT;
                                len <= rbyte;
                                len_err <= !is_burst && rbyte != 0;
                            end
                            PH_DAT: begin
                                csr_writedata <= rbyte;
                                csr_write <= !crc_on || is_burst;
                                has_data <= crc_on;
                                len <= len - 1'd1;
                                if (crc_on && len == 0)
                                    ph <= PH_CRC0;
                            end
                            PH_CRC0:
                                ph <= PH_CRC1;
                            PH_CRC1: begin
                                ph <= PH_END;
                                ack <= crc_pass; // no ack for a rejected write
                                if (crc_pass) begin
                                    xfer_bad <= 0;
                                    wr_tog <= !wr_tog;
                                    csr_write <= !is_burst; // the byte held in csr_writedata
                                end
                            end
                            default:
                                ack <= 0;
                        endcase
                    end
                end
                else if (bit_cnt == 8) begin
                    if (!ack && sda_in_d)
                        is_skip <= 1;
                    if (is_addr_byte) begin
                        is_addr_byte <= 0;
                    end
                    else if (!is_write) begin
                        if (!crc_on) begin
                            csr_read <= 1;
                        end
                        else begin
                            case (ph)
                                PH_STAT:
                                    ph <= PH_DAT;
                                PH_DAT: begin
                                    csr_read <= 1;
                                    len <= len - 1'd1;
                                    if (len == 0)
                                        ph <= PH_CRC0;
                                end
                                PH_CRC0:
                                    ph <= PH_CRC1;
                                PH_CRC1:
                                    ph <= PH_END;
                                default: ;
                            endcase
                        end
                    end
                end
            end
            else if (scl_falling) begin
                bit_cnt <= bit_cnt + 1'b1;
                
                if (is_write) begin
                    sda_out <= 1;
                end
                else begin
                    case (bit_cnt)
                        8: sda_out <= tbyte[7];
                        0: sda_out <= tbyte[6];
                        1: sda_out <= tbyte[5];
                        2: sda_out <= tbyte[4];
                        3: sda_out <= tbyte[3];
                        4: sda_out <= tbyte[2];
                        5: sda_out <= tbyte[1];
                        6: sda_out <= tbyte[0];
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
