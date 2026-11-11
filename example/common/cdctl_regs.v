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

// chip-level registers: the addresses with bit5 set, the others belong to the core
module cdctl_regs(
        input       clk,
        input       reset_n,

        input       [5:0] csr_address,
        input       csr_read,
        output      [7:0] csr_readdata,
        input       csr_write,
        input       [7:0] csr_writedata,

        output      core_read,
        input       [7:0] core_readdata,
        output      core_write,

        output reg  int_push_pull,  // int pin: push-pull instead of open-drain
        output reg  int_pull_up,    // int pin: pull-up of the pad
        output reg  re_out_en,      // re pin: push-pull instead of high impedance
        output reg  re_out,         // re pin: output value
        output reg  crc_en,         // crc mode of the host interface
        output reg  sdo_early       // spi and qspi: output data 1/2 sck cycle early
    );

localparam
    REG_INTF_CFG        = 'h38,
    REG_PIN_RE_CTRL     = 'h39;

wire is_core = !csr_address[5];
assign core_read = csr_read && is_core;
assign core_write = csr_write && is_core;

reg [7:0] readdata;
assign csr_readdata = is_core ? core_readdata : readdata;

always @(*)
    case (csr_address)
        REG_INTF_CFG:
            readdata = {2'd0, int_pull_up, int_push_pull, 2'd0, sdo_early, crc_en};
        REG_PIN_RE_CTRL:
            readdata = {3'd0, re_out_en, 3'd0, re_out};
        default:
            readdata = 0;
    endcase

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        int_push_pull <= 0;
        int_pull_up <= 0;
        re_out_en <= 0;
        re_out <= 0;
        crc_en <= 0;
        sdo_early <= 0;
    end
    else if (csr_write) begin
        case (csr_address)
            REG_INTF_CFG: begin
                int_pull_up <= csr_writedata[5];
                int_push_pull <= csr_writedata[4];
                sdo_early <= csr_writedata[1];
`ifdef CD_CSR_CRC
                crc_en <= csr_writedata[0];
`endif
            end
            REG_PIN_RE_CTRL: begin
                re_out_en <= csr_writedata[4];
                re_out <= csr_writedata[0];
            end
        endcase
    end

endmodule
