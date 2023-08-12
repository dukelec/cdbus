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
        parameter VERSION = 8'h0f,
        parameter DIV_LS = 346, // default: 115200 bps for 40MHz clk
        parameter DIV_HS = 346
    )(
        input               clk,
        input               reset_n,
        output              irq,
`ifdef HAS_CHIP_SELECT
        input               chip_select,
`endif

        input       [3:0]   csr_address,
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
        output reg  [7:0]   filter_m0,
        output reg  [7:0]   filter_m1,
        output reg  [15:0]  div_ls,
        output reg  [15:0]  div_hs,

        output reg          rx_clean_all,
        output reg          rx_ram_rd_done,
        output reg  [5:0]   rx_ram_rd_addr,
        input      [31:0]   rx_ram_rd_word,
        input       [7:0]   rx_ram_rd_len,
        input               rx_ram_rd_err,
        input               rx_error,
        input               rx_ram_lost,
        input               rx_break,
        input               rx_pending,
        input               bus_idle,

        output              tx_ram_wr_en,
        output reg  [5:0]   tx_ram_wr_addr,
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
    REG_INT_MASK        = 'h09,
    REG_INT_FLAG        = 'h0a,
    REG_RX              = 'h0b,
    REG_TX              = 'h0c,
    REG_RX_CTRL         = 'h0d,
    REG_TX_CTRL         = 'h0e,
    REG_FILTER_M        = 'h0f;

reg tx_error_flag;
reg cd_flag;
reg rx_error_flag;
reg rx_lost_flag;
reg rx_break_flag;

reg idle_invert;
reg [7:0] int_mask;
wire [7:0] int_flag = {tx_error_flag, cd_flag, ~tx_pending, (not_drop ? rx_ram_rd_err : rx_error_flag),
                       rx_lost_flag, rx_break_flag, rx_pending, (idle_invert ? ~bus_idle : bus_idle)};

`ifdef HAS_CHIP_SELECT
reg has_read_rx;
reg chip_select_delayed;
reg [7:0] int_flag_snapshot;    // avoid metastability due to int_flag
`endif

assign tx_ram_wr_en = (csr_address == REG_TX) ? csr_write : 1'b0;

assign irq = (int_flag & int_mask) != 0;


always @(*)
    case (csr_address)
        REG_VERSION:
            csr_readdata = {24'd0, VERSION};
        REG_SETTING:
            csr_readdata = {24'd0, idle_invert, full_duplex, break_sync, arbitration,
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
        REG_INT_MASK:
            csr_readdata = {24'd0, int_mask};
        REG_INT_FLAG:
`ifdef HAS_CHIP_SELECT
            csr_readdata = {16'd0, rx_ram_rd_len, int_flag_snapshot};
`else
            csr_readdata = {16'd0, rx_ram_rd_len, int_flag};
`endif
        REG_RX:
            csr_readdata = rx_ram_rd_word;
        REG_FILTER_M:
            csr_readdata = {16'd0, filter_m1, filter_m0};
        default:
            csr_readdata = 0;
    endcase


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        idle_invert <= 0;
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
        filter_m0 <= 8'hff;
        filter_m1 <= 8'hff;
        div_ls <= DIV_LS;
        div_hs <= DIV_HS;

        tx_error_flag <= 0;
        cd_flag <= 0;
        rx_error_flag <= 0;
        rx_lost_flag <= 0;
        rx_break_flag <= 0;

        int_mask <= 0;
`ifdef HAS_CHIP_SELECT
        chip_select_delayed <= 0;
        int_flag_snapshot <= 0;
        has_read_rx <= 0;
`endif

        rx_ram_rd_addr <= 0;
        rx_ram_rd_done <= 0;
        rx_clean_all <= 0;

        tx_ram_wr_addr <= 0;
        tx_ram_switch <= 0;
        tx_abort <= 0;
        has_break <= 0;
    end
    else begin
        rx_ram_rd_done <= 0;
        rx_clean_all <= 0;
        tx_ram_switch <= 0;
        tx_abort <= 0;

`ifdef HAS_CHIP_SELECT
        chip_select_delayed <= chip_select;
        if (!chip_select) begin
            int_flag_snapshot <= int_flag;
            rx_ram_rd_addr <= 0;
            tx_ram_wr_addr <= 0;
            has_read_rx <= 0;
            if (chip_select_delayed && has_read_rx)
                rx_ram_rd_done <= 1; // auto release rx page
        end
`endif

        if (csr_read) begin
            if (csr_address == REG_INT_FLAG) begin
                rx_error_flag <= 0;
                rx_lost_flag <= 0;
                rx_break_flag <= 0;
                cd_flag <= 0;
                tx_error_flag <= 0;
            end
            else if (csr_address == REG_RX) begin
                rx_ram_rd_addr <= rx_ram_rd_addr + 1'd1;
`ifdef HAS_CHIP_SELECT
                has_read_rx <= 1;
`endif
            end
        end

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
                REG_SETTING: begin
                    idle_invert <= csr_writedata[7];
                    full_duplex <= csr_writedata[6];
                    break_sync <= csr_writedata[5];
                    arbitration <= csr_writedata[4];
                    not_drop <= csr_writedata[3];
                    user_crc <= csr_writedata[2];
                    tx_invert <= csr_writedata[1];
                    tx_push_pull <= csr_writedata[0];
                end
                REG_IDLE_WAIT_LEN:
                    idle_wait_len <= csr_writedata[7:0];
                REG_TX_PERMIT_LEN:
                    tx_permit_len[9:0] <= csr_writedata[9:0];
                REG_MAX_IDLE_LEN:
                    max_idle_len[9:0] <= csr_writedata[9:0];
                REG_TX_PRE_LEN:
                    tx_pre_len <= csr_writedata[1:0];
                REG_FILTER:
                    filter <= csr_writedata[7:0];
                REG_DIV_LS:
                    div_ls[15:0] <= csr_writedata[15:0];
                REG_DIV_HS:
                    div_hs[15:0] <= csr_writedata[15:0];
                REG_INT_MASK:
                    int_mask <= csr_writedata[7:0];
                REG_TX:
                    tx_ram_wr_addr <= tx_ram_wr_addr + 1'd1;
                REG_RX_CTRL: begin
                    if (csr_writedata[4])
                        rx_clean_all <= 1;
                    if (csr_writedata[1])
                        rx_ram_rd_done <= 1;
`ifndef HAS_CHIP_SELECT
                    rx_ram_rd_addr <= 0;
`endif
                end
                REG_TX_CTRL: begin
                    if (csr_writedata[5])
                        has_break <= 1;
                    if (csr_writedata[4])
                        tx_abort <= 1;
                    if (csr_writedata[1])
                        tx_ram_switch <= 1;
`ifndef HAS_CHIP_SELECT
                    tx_ram_wr_addr <= 0;
`endif
                end
                REG_FILTER_M: begin
                    filter_m0 <= csr_writedata[7:0];
                    filter_m1 <= csr_writedata[15:8];
                end
            endcase
    end

endmodule

