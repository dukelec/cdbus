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

module cd_csr
    #(
        parameter VERSION = 8'd12,
        parameter DIV_LS = 346, // default: 115200 bps for 40MHz clk
        parameter DIV_HS = 346
    )(
        input               clk,
        input               reset_n,
        output              irq,

        input       [3:0]   csr_address,
        input       [3:0]   csr_byteenable,
        input               csr_read,
        output reg  [31:0]  csr_readdata,
        input               csr_write,
        input       [31:0]  csr_writedata,

        output reg          full_duplex,
        output reg          break_sync,
        output reg          arbitration,
        output reg          not_drop,
        output reg          user_crc,
        output reg          tx_invert,
        output reg          tx_push_pull,

        output reg  [7:0]   idle_wait_len,
        output reg  [9:0]   tx_permit_len,
        output reg  [9:0]   max_idle_len,
        output reg  [1:0]   tx_pre_len,
        output reg  [7:0]   filter,
        output reg  [7:0]   filter1,
        output reg  [7:0]   filter2,
        output reg  [15:0]  div_ls,
        output reg  [15:0]  div_hs,

        output reg          rx_ram_rd_done,
        output reg          rx_clean_all,
        input       [7:0]   rx_ram_rd_flags,
        input               rx_error,
        input               rx_ram_lost,
        input               rx_break,
        input               rx_pending,
        input               bus_idle,

        output reg          tx_ram_switch,
        output reg          tx_abort,
        output reg          has_break,
        input               ack_break,
        input               tx_pending,
        input               cd,
        input               tx_err
    );

localparam
    REG_VERSION         = 'h00,
    REG_SETTING         = 'h01,
    REG_IDLE_WAIT_LEN   = 'h02,
    REG_TX_PERMIT_LEN   = 'h03,
    REG_MAX_IDLE_LEN    = 'h04,
    REG_TX_PRE_LEN      = 'h05,
    REG_FILTER          = 'h06,
    REG_DIV_LS          = 'h07,
    REG_DIV_HS          = 'h08,
    REG_INT_FLAG        = 'h09,
    REG_INT_MASK        = 'h0a,
    REG_RX_CTRL         = 'h0b,
    REG_TX_CTRL         = 'h0c,
    REG_RX_PAGE_FLAG    = 'h0d,
    REG_FILTER_M        = 'h0e;

reg tx_error_flag;
reg cd_flag;
reg rx_error_flag;
reg rx_lost_flag;
reg rx_break_flag;

reg [7:0] int_mask;
wire [7:0] int_flag = {tx_error_flag, cd_flag, ~tx_pending, rx_error_flag,
                       rx_lost_flag, rx_break_flag, rx_pending, bus_idle};

assign irq = (int_flag & int_mask) != 0;


always @(*)
    case (csr_address)
        REG_VERSION:
            csr_readdata = {24'd0, VERSION};
        REG_SETTING:
            csr_readdata = {25'd0, full_duplex, break_sync, arbitration,
                            not_drop, user_crc, tx_invert, tx_push_pull};
        REG_IDLE_WAIT_LEN:
            csr_readdata = {24'd0, idle_wait_len};
        REG_TX_PERMIT_LEN:
            csr_readdata = {22'd0, tx_permit_len};
        REG_MAX_IDLE_LEN:
            csr_readdata = {22'd0, max_idle_len};
        REG_TX_PRE_LEN:
            csr_readdata = {30'd0, tx_pre_len};
        REG_FILTER:
            csr_readdata = {24'd0, filter};
        REG_DIV_LS:
            csr_readdata = {24'd0, div_ls};
        REG_DIV_HS:
            csr_readdata = {24'd0, div_hs};
        REG_INT_FLAG:
            csr_readdata = {24'd0, int_flag};
        REG_INT_MASK:
            csr_readdata = {24'd0, int_mask};
        REG_RX_PAGE_FLAG:
            csr_readdata = {24'd0, rx_ram_rd_flags};
        REG_FILTER_M:
            csr_readdata = {16'd0, filter2, filter1};
        default:
            csr_readdata = 0;
    endcase


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        full_duplex <= 0;
        break_sync <= 0;
        arbitration <= 1;
        not_drop <= 0;
        user_crc <= 0;
        tx_invert <= 0;
        tx_push_pull <= 0;

        idle_wait_len <= 10;
        tx_permit_len <= 20;
        max_idle_len <= 200;
        tx_pre_len <= 1;
        filter <= 8'hff;
        filter1 <= 8'hff;
        filter2 <= 8'hff;
        div_ls <= DIV_LS;
        div_hs <= DIV_HS;

        tx_error_flag <= 0;
        cd_flag <= 0;
        rx_error_flag <= 0;
        rx_lost_flag <= 0;
        rx_break_flag <= 0;

        int_mask <= 0;

        rx_ram_rd_done <= 0;
        rx_clean_all <= 0;

        tx_ram_switch <= 0;
        tx_abort <= 0;
        has_break <= 0;
    end
    else begin
        rx_ram_rd_done <= 0;
        rx_clean_all <= 0;
        tx_ram_switch <= 0;
        tx_abort <= 0;

        if (rx_error)
            rx_error_flag <= 1;
        if (rx_ram_lost)
            rx_lost_flag <= 1;
        if (rx_break)
            rx_break_flag <= 1;
        if (cd)
            cd_flag <= 1;
        if (tx_err)
            tx_error_flag <= 1;
        if (ack_break)
            has_break <= 0;

        if (csr_write)
            case (csr_address)
                REG_SETTING:
                    if (csr_byteenable[0]) begin
                        full_duplex <= csr_writedata[6];
                        break_sync <= csr_writedata[5];
                        arbitration <= csr_writedata[4];
                        not_drop <= csr_writedata[3];
                        user_crc <= csr_writedata[2];
                        tx_invert <= csr_writedata[1];
                        tx_push_pull <= csr_writedata[0];
                    end
                REG_IDLE_WAIT_LEN:
                    if (csr_byteenable[0])
                        idle_wait_len <= csr_writedata[7:0];
                REG_TX_PERMIT_LEN: begin
                    if (csr_byteenable[0])
                        tx_permit_len[7:0] <= csr_writedata[7:0];
                    if (csr_byteenable[1])
                        tx_permit_len[9:8] <= csr_writedata[9:8];
                end
                REG_MAX_IDLE_LEN: begin
                    if (csr_byteenable[0])
                        max_idle_len[7:0] <= csr_writedata[7:0];
                    if (csr_byteenable[1])
                        max_idle_len[9:8] <= csr_writedata[9:8];
                end
                REG_TX_PRE_LEN:
                    if (csr_byteenable[0])
                        tx_pre_len <= csr_writedata[1:0];
                REG_FILTER:
                    if (csr_byteenable[0])
                        filter <= csr_writedata[7:0];
                REG_DIV_LS: begin
                    if (csr_byteenable[0])
                        div_ls[7:0] <= csr_writedata[7:0];
                    if (csr_byteenable[1])
                        div_ls[15:8] <= csr_writedata[15:8];
                end
                REG_DIV_HS: begin
                    if (csr_byteenable[0])
                        div_hs[7:0] <= csr_writedata[7:0];
                    if (csr_byteenable[1])
                        div_hs[15:8] <= csr_writedata[15:8];
                end
                REG_INT_MASK:
                    if (csr_byteenable[0])
                        int_mask <= csr_writedata[7:0];
                REG_RX_CTRL:
                    if (csr_byteenable[0]) begin
                        if (csr_writedata[1])
                            rx_ram_rd_done <= 1;
                        if (csr_writedata[2])
                            rx_lost_flag <= 0;
                        if (csr_writedata[3])
                            rx_error_flag <= 0;
                        if (csr_writedata[4])
                            rx_clean_all <= 1;
                        if (csr_writedata[5])
                            rx_break_flag <= 0;
                    end
                REG_TX_CTRL:
                    if (csr_byteenable[0]) begin
                        if (csr_writedata[1])
                            tx_ram_switch <= 1;
                        if (csr_writedata[2])
                            cd_flag <= 0;
                        if (csr_writedata[3])
                            tx_error_flag <= 0;
                        if (csr_writedata[4])
                            tx_abort <= 1;
                        if (csr_writedata[5])
                            has_break <= 1;
                    end
                REG_FILTER_M: begin
                    if (csr_byteenable[0])
                        filter1 <= csr_writedata[7:0];
                    if (csr_byteenable[1])
                        filter2 <= csr_writedata[15:8];
                end
            endcase
    end

endmodule

