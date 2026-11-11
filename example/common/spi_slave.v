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

module spi_slave
    #(
        parameter A_WIDTH = 5,
        parameter DAT_ADDR = 'h15,  // crc mode: the two addresses written byte by byte,
        parameter HOLD_ADDR = 'h17  // any other address takes one byte after the crc check
    )(
        input       clk,
        input       reset_n,
        output      chip_select,
        input       sdo_early,  // output sdo 1/2 sck cycle early

        input       crc_en,     // crc mode, changes between transfers only
        output      csr_cancel, // crc mode: no valid write in this transfer, stable at its end

        output reg  [(A_WIDTH-1):0] csr_address,
        output      csr_read,
        input       [7:0] csr_readdata,
        output      csr_write,
        output reg  [7:0] csr_writedata,

        input       sck,
        input       nss,
        input       sdi,
`ifndef CD_SHARING_IO
        output      sdo
`else
        output      sdo,
        output      sdo_en
`endif
    );

// crc mode, crc16 (ccitt-false, msb first) over all the bytes before it:
//   write: cmd, n-1, n data bytes, crc16
//   read:  cmd, n-1, write status, n data bytes, crc16 (sdo driven after n-1 only: 3-wire as well)
localparam
    PH_CMD  = 3'd0,
    PH_LEN  = 3'd1,
    PH_STA  = 3'd2, // read only: write status on sdo
    PH_DAT  = 3'd3, // the only phase after cmd without crc mode
    PH_CRC0 = 3'd4,
    PH_CRC1 = 3'd5,
    PH_END  = 3'd6;

reg [2:0] nss_d;
always @(posedge clk)
    nss_d <= {nss_d[1:0], nss};
assign chip_select = !nss_d[2];

wire spi_reset_n = reset_n && !nss;
reg  [2:0] bit_cnt;
reg  [6:0] rreg;
reg  [7:0] treg;
reg  [2:0] ph;
reg  is_write;
reg  crc_on;
reg  [7:0] len;     // data bytes left after the current one
reg  len_err;       // more than one byte for an address which takes only one
reg  [15:0] crc;
reg  sdo_dat_en;
reg  sdo_dat_en_d;
reg  treg7_d;

wire _sdo_en = sdo_early ? sdo_dat_en : sdo_dat_en_d;
wire _sdo = sdo_early ? treg[7] : treg7_d;

`ifndef CD_SHARING_IO
    assign sdo = (spi_reset_n && _sdo_en) ? _sdo : 1'bz;
`else
    assign sdo = _sdo;
    assign sdo_en = spi_reset_n && _sdo_en;
`endif

wire [7:0] rbyte = {rreg, sdi};
wire byte_end = (bit_cnt == 7); // rising edge of the last bit
wire is_burst = (csr_address == DAT_ADDR) || (csr_address == HOLD_ADDR);

// read: the crc continues with the bits sent, they are at treg[7] one by one
wire crc_din = (is_write || ph <= PH_LEN) ? sdi : treg[7];
wire [15:0] crc_nxt = {crc[14:0], 1'b0} ^ ({16{crc[15] ^ crc_din}} & 16'h1021);
wire crc_pass = (crc_nxt == 0) && !len_err; // at the last bit of a write

reg  w_tog; // toggle once per event, immune to pulse-width loss across domains
reg  r_tog;
reg  wr_tog; // toggle once per accepted write of crc mode, reported by the next read
reg  xfer_bad;
reg  [2:0] event_wd;
reg  [2:0] event_rd;
assign csr_write = event_wd[2] ^ event_wd[1];
assign csr_read = event_rd[2] ^ event_rd[1];
assign csr_cancel = xfer_bad;

// toggles must survive the end of transfer, do not reset with spi_reset_n,
// otherwise the clk domain would take the async clear as an extra event
always @(posedge sck or negedge reset_n)
    if (!reset_n) begin
        w_tog <= 0;
        r_tog <= 0;
        wr_tog <= 0;
        xfer_bad <= 0;
    end
    else begin
        if (ph == PH_CMD && byte_end)
            xfer_bad <= crc_on;

        if (ph == PH_DAT) begin
            if (is_write) begin
                if (byte_end && (!crc_on || is_burst)) // each data byte
                    w_tog <= !w_tog;
            end
            else begin
                if (bit_cnt == 0) // rising edge of bit 1 of each data byte
                    r_tog <= !r_tog;
            end
        end

        if (ph == PH_CRC1 && byte_end && is_write && crc_pass) begin
            xfer_bad <= 0;
            wr_tog <= !wr_tog;
            if (!is_burst)
                w_tog <= !w_tog; // the byte held in csr_writedata
        end
    end


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        event_wd <= 0;
        event_rd <= 0;
    end
    else begin
        event_wd <= {event_wd[1:0], w_tog};
        event_rd <= {event_rd[1:0], r_tog};
    end


// read from sdi
always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        bit_cnt <= 0;
        rreg <= 0;
        ph <= PH_CMD;
        is_write <= 0;
        crc_on <= 0;
        len <= 0;
        len_err <= 0;
        crc <= 16'hffff;
    end
    else begin
        rreg <= {rreg[5:0], sdi};
        bit_cnt <= bit_cnt + 1'b1;

        if (ph <= PH_DAT || (is_write && ph <= PH_CRC1))
            crc <= crc_nxt;

        if (ph == PH_CMD && bit_cnt == 6) begin // rising edge of penultimate bit
            is_write <= rreg[5]; // MSB
            csr_address <= {rreg[(A_WIDTH-2):0], sdi};
            crc_on <= crc_en;
        end

        if (byte_end)
            case (ph)
                PH_CMD:
                    ph <= crc_on ? PH_LEN : PH_DAT;
                PH_LEN: begin
                    ph <= is_write ? PH_DAT : PH_STA;
                    len <= rbyte;
                    len_err <= is_write && !is_burst && rbyte != 0;
                end
                PH_STA:
                    ph <= PH_DAT;
                PH_DAT: begin
                    csr_writedata <= rbyte;
                    len <= len - 1'd1;
                    if (crc_on && len == 0)
                        ph <= PH_CRC0;
                end
                PH_CRC0:
                    ph <= PH_CRC1;
                PH_CRC1:
                    ph <= PH_END;
                default: ;
            endcase
    end


// write to sdo
always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        treg <= 0;
        sdo_dat_en <= 0;
    end
    else begin
        if (!is_write && byte_end && !(crc_on && ph == PH_CMD))
            sdo_dat_en <= 1; // rising edge of the last bit from the host: cmd, crc mode: n-1

        if (byte_end)
            case (ph)
                PH_CMD, PH_STA:
                    treg <= csr_readdata;
                PH_LEN:
                    treg <= wr_tog ? 8'h0f : 8'hf0;
                PH_DAT:
                    treg <= (crc_on && len == 0) ? crc_nxt[15:8] : csr_readdata;
                PH_CRC0:
                    treg <= crc[7:0];
                default:
                    treg <= 0;
            endcase
        else
            treg <= {treg[6:0], 1'b0};
    end


always @(negedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        sdo_dat_en_d <= 0;
    end
    else begin
        sdo_dat_en_d <= sdo_dat_en;
        treg7_d <= treg[7];
    end


endmodule
