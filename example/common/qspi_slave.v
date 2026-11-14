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

module qspi_slave
    #(
        parameter A_WIDTH = 5,
        parameter DAT_ADDR = 'h15,  // crc mode: the two addresses written byte by byte,
        parameter HOLD_ADDR = 'h17  // any other address takes one byte after the crc check
    )(
        input       clk,
        input       reset_n,
        output      chip_select,
        input       sdo_early, // output sdo 1/2 sck cycle early

        input       crc_en,     // crc mode, changes between transfers only
        output      csr_cancel, // crc mode: data written without a valid crc, kept after the transfer

        output reg  [(A_WIDTH-1):0] csr_address,
        output      csr_read,
        input       [7:0] csr_readdata,
        output reg  csr_write,
        output reg  [7:0] csr_writedata,

        input       sck,
        input       nss,
`ifndef CD_SHARING_IO
        inout       [3:0] sdio
`else
        input       [3:0] sdi,
        output      [3:0] sdo,
        output      sdo_en
`endif
    );

// crc mode, crc16 (ccitt-false, msb first) over all the bytes before it, the dummy left out:
//   write: cmd, n-1, n data bytes, crc16
//   read:  cmd, n-1, dummy, write status, n data bytes, crc16
localparam
    PH_CMD  = 3'd0,
    PH_LEN  = 3'd1,
    PH_DAT  = 3'd2, // the only phase after cmd without crc mode
    PH_CRC0 = 3'd3,
    PH_CRC1 = 3'd4,
    PH_END  = 3'd5;

localparam // content of treg
    OUT_NONE = 2'd0,
    OUT_STA  = 2'd1,
    OUT_DAT  = 2'd2,
    OUT_CRC  = 2'd3;

reg [3:0] nss_d;
always @(posedge clk)
    nss_d <= {nss_d[2:0], nss};
assign chip_select = !nss_d[3] || !nss_d[2];

wire spi_reset_n = reset_n && !nss;
reg  bit_cnt;
reg  [7:0] rreg;
reg  [7:0] treg;
reg  [1:0] byte_cnt;
reg  [2:0] ph;
reg  is_write;
reg  crc_on;
reg  [7:0] len;     // data bytes left: to write, or to fetch for a read
reg  len_err;       // more than one byte for an address which takes only one
reg  [15:0] crc;
reg  [1:0] fetch_d; // read events at the end of the last two bytes
reg  [1:0] out;
reg  sdo_dat_en;
reg  sdo_dat_en_d;
reg  [3:0] treg74_d;

wire _sdo_en = sdo_early ? sdo_dat_en : sdo_dat_en_d;
wire [3:0] _sdo = sdo_early ? treg[7:4] : treg74_d;

`ifndef CD_SHARING_IO
    assign sdio = (spi_reset_n && _sdo_en) ? _sdo : 4'bz;
    wire [3:0] sdi = sdio;
`else
    assign sdo = _sdo;
    assign sdo_en = spi_reset_n && _sdo_en;
`endif

wire [7:0] rbyte = {rreg[3:0], sdi};
wire is_burst = (csr_address == DAT_ADDR) || (csr_address == HOLD_ADDR);

function [15:0] crc_nibble(input [15:0] c, input [3:0] d);
    integer i;
    begin
        crc_nibble = c;
        for (i = 3; i >= 0; i = i - 1)
            crc_nibble = {crc_nibble[14:0], 1'b0} ^ ({16{crc_nibble[15] ^ d[i]}} & 16'h1021);
    end
endfunction

// read: the crc continues with the nibbles sent, the dummy is left out
wire rd_out = !is_write && (out == OUT_STA || out == OUT_DAT);
wire crc_run = is_write ? (ph <= PH_CRC1) : (ph <= PH_LEN || rd_out);
wire [15:0] crc_nxt = crc_nibble(crc, rd_out ? treg[7:4] : sdi);
wire crc_pass = (crc_nxt == 0) && !len_err; // at the last nibble of a write

// read events run two bytes ahead of treg; crc mode: n events, the first at the end of n-1
wire fetch = !is_write && (!crc_on || ph == PH_LEN || (ph == PH_DAT && len != 0));

reg  w_tog; // toggle once per event, immune to pulse-width loss across domains
reg  r_tog;
reg  wr_tog;    // toggle once per accepted write of crc mode, reported by the next read
reg  xfer_bad;
reg  [2:0] event_wd;
reg  [2:0] event_rd;
wire csr_write_ = event_wd[2] ^ event_wd[1];
assign csr_read = event_rd[2] ^ event_rd[1];
assign csr_cancel = xfer_bad;

reg [7:0] csr_writedata_d0;
reg [7:0] csr_writedata_d1;

reg [7:0] ram[1:0]; // FIFO
reg ra;
reg wa;

reg csr_read_d;

always @(posedge clk) begin
    csr_read_d <= csr_read;
    if (!chip_select) begin
        wa <= 0;
    end
    else if (csr_read_d) begin // data is valid in the clock after csr_read
        ram[wa] <= csr_readdata;
        wa <= !wa;
    end
end


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        event_rd <= 0;
        event_wd <= 0;
        csr_write <= 0;
    end
    else begin
        event_wd <= {event_wd[1:0], w_tog};
        event_rd <= {event_rd[1:0], r_tog};
        csr_writedata_d1 <= csr_writedata_d0;
        csr_writedata <= csr_writedata_d1;
        csr_write <= csr_write_; // wait for csr_writedata stable
    end


// read from sdi
always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        bit_cnt <= 0;
        rreg <= 0;
        byte_cnt <= 0;
        ph <= PH_CMD;
        is_write <= 0;
        crc_on <= 0;
        len <= 0;
        len_err <= 0;
        crc <= 16'hffff;
    end
    else begin
        rreg <= {rreg[3:0], sdi};
        bit_cnt <= !bit_cnt;

        if (crc_run)
            crc <= crc_nxt;

        if (bit_cnt) begin // rising edge of end of byte
            if (byte_cnt != 2'd3)
                byte_cnt <= byte_cnt + 1'd1;

            case (ph)
                PH_CMD: begin
                    csr_address <= {rreg[(A_WIDTH-5):0], sdi};
                    ph <= crc_on ? PH_LEN : PH_DAT;
                end
                PH_LEN: begin
                    ph <= PH_DAT;
                    len <= rbyte;
                    len_err <= is_write && !is_burst && rbyte != 0;
                end
                PH_DAT: begin
                    csr_writedata_d0 <= rbyte;
                    if (len != 0) begin
                        len <= len - 1'd1;
                    end
                    else if (crc_on && is_write) begin
                        ph <= PH_CRC0;
                    end
                end
                PH_CRC0:
                    ph <= PH_CRC1;
                PH_CRC1:
                    ph <= PH_END;
                default: ;
            endcase
        end
        else if (byte_cnt == 0) begin
            is_write <= sdi[3]; // MSB, captured half byte early
            crc_on <= crc_en;
        end
    end


// toggles must survive the end of transfer, do not reset with spi_reset_n,
// otherwise the clk domain would take the async clear as an extra event
always @(posedge sck or negedge reset_n)
    if (!reset_n) begin
        w_tog <= 0;
        r_tog <= 0;
        wr_tog <= 0;
        xfer_bad <= 0;
    end
    else if (bit_cnt) begin // rising edge of end of byte
        if (fetch)
            r_tog <= !r_tog;

        if (is_write) begin
            if (ph == PH_DAT && (!crc_on || is_burst)) begin // each data byte
                w_tog <= !w_tog;
                xfer_bad <= crc_on; // not earlier: the core takes the last transfer's value some clocks after nss
            end

            if (ph == PH_CRC1 && crc_pass) begin
                xfer_bad <= 0;
                wr_tog <= !wr_tog;
                if (!is_burst)
                    w_tog <= !w_tog; // the byte held in csr_writedata_d0
            end
        end
    end


// write to sdo

always @(posedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        treg <= 0;
        sdo_dat_en <= 0;
        ra <= 0;
        fetch_d <= 0;
        out <= OUT_NONE;
    end
    else begin
        if (!is_write && byte_cnt[1] && bit_cnt)
            sdo_dat_en <= 1; // rising edge of the third byte's last bit

        if (bit_cnt)
            fetch_d <= {fetch_d[0], fetch};

        if (bit_cnt && fetch_d[1]) begin
            treg <= ram[ra];
            ra <= !ra;
            out <= OUT_DAT;
        end
        else if (bit_cnt && crc_on && byte_cnt == 2'd2) begin
            treg <= wr_tog ? 8'h0f : 8'hf0;
            out <= OUT_STA;
        end
        else if (bit_cnt && crc_on && out == OUT_DAT) begin
            treg <= crc_nxt[15:8];
            out <= OUT_CRC;
        end
        else if (bit_cnt && out == OUT_CRC) begin
            treg <= crc[7:0];
            out <= OUT_NONE;
        end
        else begin
            treg <= {treg[3:0], 4'b0};
        end
    end


always @(negedge sck or negedge spi_reset_n)
    if (!spi_reset_n) begin
        sdo_dat_en_d <= 0;
    end
    else begin
        sdo_dat_en_d <= sdo_dat_en;
        treg74_d <= treg[7:4];
    end


endmodule
