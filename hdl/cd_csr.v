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

        input       [4:0]   csr_address,
        input               csr_read,
        output reg  [7:0]   csr_readdata,
        input               csr_write,
        input       [7:0]   csr_writedata,

        output reg          tx_en_inner,
        output reg          rx_invert,
        output              full_duplex,
        output              break_sync,
        output              arbitration,
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
        output reg  [7:0]   rx_ram_rd_addr,
        input       [7:0]   rx_ram_rd_byte,
        input       [7:0]   rx_ram_rd_len,
        input               rx_ram_rd_err,
        input               rx_error,
        input               rx_ram_lost,
        input               rx_break,
        input               rx_pending,
        input       [5:0]   rx_pend_len,
        input               bus_idle,

        input               tx_ram_full,
        output              tx_ram_wr_en,
        output reg  [7:0]   tx_ram_wr_addr,
        output reg          tx_ram_wr_done,
        output reg          tx_abort,
        output reg          tx_drop,
        output reg          has_break,
        input               ack_break,
        input               tx_pending,
        input               cd,
        input               tx_err
    );

localparam
    REG_VERSION         = 'h00,
    REG_SETTING         = 'h02,
    REG_IDLE_WAIT_LEN   = 'h04,
    REG_TX_PERMIT_LEN_L = 'h05,
    REG_TX_PERMIT_LEN_H = 'h06,
    REG_MAX_IDLE_LEN_L  = 'h07,
    REG_MAX_IDLE_LEN_H  = 'h08,
    REG_TX_PRE_LEN      = 'h09,
    REG_FILTER          = 'h0b,
    REG_DIV_LS_L        = 'h0c,
    REG_DIV_LS_H        = 'h0d,
    REG_DIV_HS_L        = 'h0e,
    REG_DIV_HS_H        = 'h0f,
    REG_INT_MASK_L      = 'h10,
    REG_INT_MASK_H      = 'h11,
    REG_INT_FLAG_L      = 'h12,
    REG_INT_FLAG_H      = 'h13,
    REG_RX_LEN          = 'h14,
    REG_DAT             = 'h15,
    REG_CTRL            = 'h16,
    REG_FILTER_M0       = 'h1a,
    REG_FILTER_M1       = 'h1b;

reg tx_error_flag;
reg cd_flag;
reg rx_error_flag;
reg rx_lost_flag;
reg rx_break_flag;

reg [1:0] mode_sel;
reg [15:0] int_mask;
wire [15:0] int_flag = {~bus_idle, bus_idle, rx_pend_len,
                        tx_error_flag, cd_flag, ~tx_pending, ~tx_ram_full,
                       (not_drop ? rx_ram_rd_err : rx_error_flag), rx_lost_flag, rx_break_flag, rx_pending};
reg [7:0] h_val_bkup;

`ifdef HAS_CHIP_SELECT
reg has_read_rx;
reg has_write_tx;
reg chip_select_delayed;
reg [23:0] int_flag_shift;
reg [15:0] int_flag_snapshot;

always @(posedge clk) begin
        if (!chip_select) begin
            // avoid metastability
            int_flag_snapshot <= int_flag;
            int_flag_shift <= {int_flag[15:8], rx_ram_rd_len, int_flag[7:0]};
        end
        else if (csr_read) begin
            int_flag_shift <= {8'd0, int_flag_shift[23:8]};
        end
    end
`endif

assign tx_ram_wr_en = (csr_address == REG_DAT) ? csr_write : 1'b0;

assign irq = (int_flag & int_mask) != 0;
assign full_duplex = mode_sel == 2'd3;
assign break_sync = mode_sel == 2'd2;
assign arbitration = mode_sel == 2'd1;


always @(*)
    case (csr_address)
        REG_VERSION:
            csr_readdata = VERSION;
        REG_SETTING:
            csr_readdata = {tx_en_inner, rx_invert, mode_sel, not_drop, user_crc, tx_invert, tx_push_pull};
        REG_IDLE_WAIT_LEN:
            csr_readdata = idle_wait_len;
        REG_TX_PERMIT_LEN_L:
            csr_readdata = tx_permit_len[7:0];
        REG_TX_PERMIT_LEN_H:
            csr_readdata = {6'd0, tx_permit_len[9:8]};
        REG_MAX_IDLE_LEN_L:
            csr_readdata = max_idle_len[7:0];
        REG_MAX_IDLE_LEN_H:
            csr_readdata = {6'd0, max_idle_len[9:8]};
        REG_TX_PRE_LEN:
            csr_readdata = {6'd0, tx_pre_len};
        REG_FILTER:
            csr_readdata = filter;
        REG_DIV_LS_L:
            csr_readdata = div_ls[7:0];
        REG_DIV_LS_H:
            csr_readdata = div_ls[15:8];
        REG_DIV_HS_L:
            csr_readdata = div_hs[7:0];
        REG_DIV_HS_H:
            csr_readdata = div_hs[15:8];
        REG_INT_MASK_L:
            csr_readdata = int_mask[7:0];
        REG_INT_MASK_H:
            csr_readdata = int_mask[15:0];

`ifdef HAS_CHIP_SELECT
        REG_INT_FLAG_L:
            csr_readdata = int_flag_shift[7:0];
        REG_INT_FLAG_H:
            csr_readdata = int_flag_snapshot[15:8];
`else
        REG_INT_FLAG_L:
            csr_readdata = int_flag[7:0];
        REG_INT_FLAG_H:
            csr_readdata = int_flag[15:0];
`endif

        REG_RX_LEN:
            csr_readdata = rx_ram_rd_len;
        REG_DAT:
            csr_readdata = rx_ram_rd_byte;
        REG_FILTER_M0:
            csr_readdata = filter_m0;
        REG_FILTER_M1:
            csr_readdata = filter_m1;
        default:
            csr_readdata = 0;
    endcase


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        tx_en_inner <= 0;
        rx_invert <= 0;
        mode_sel <= 2'b01;
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
        has_read_rx <= 0;
        has_write_tx <= 0;
`endif
        h_val_bkup <= 0;

        rx_ram_rd_addr <= 0;
        rx_ram_rd_done <= 0;
        rx_clean_all <= 0;

        tx_ram_wr_addr <= 0;
        tx_ram_wr_done <= 0;
        tx_abort <= 0;
        tx_drop <= 0;
        has_break <= 0;
    end
    else begin
        rx_ram_rd_done <= 0;
        rx_clean_all <= 0;
        tx_ram_wr_done <= 0;
        tx_abort <= 0;
        tx_drop <= 0;

`ifdef HAS_CHIP_SELECT
        chip_select_delayed <= chip_select;
        if (!chip_select) begin
            rx_ram_rd_addr <= 0;
            tx_ram_wr_addr <= 0;
            has_read_rx <= 0;
            has_write_tx <= 0;
            if (chip_select_delayed) begin
                rx_ram_rd_done <= has_read_rx;
                tx_ram_wr_done <= has_write_tx;
            end
        end
`endif

        if (csr_read) begin
            if (csr_address == REG_INT_FLAG_L) begin
`ifdef HAS_CHIP_SELECT
                if (int_flag_snapshot[3])
                    rx_error_flag <= 0; // not care when not_drop
                if (int_flag_snapshot[2])
                    rx_lost_flag <= 0;
                if (int_flag_snapshot[1])
                    rx_break_flag <= 0;
                if (int_flag_snapshot[6])
                    cd_flag <= 0;
                if (int_flag_snapshot[7])
                    tx_error_flag <= 0;
`else
                rx_error_flag <= 0;
                rx_lost_flag <= 0;
                rx_break_flag <= 0;
                cd_flag <= 0;
                tx_error_flag <= 0;
`endif
            end
            else if (csr_address == REG_DAT) begin
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
        if (csr_read || csr_write)
            h_val_bkup <= 0; // optional

        if (csr_write)
            case (csr_address)
                REG_SETTING: begin
                    tx_en_inner <= csr_writedata[7];
                    rx_invert <= csr_writedata[6];
                    mode_sel <= csr_writedata[5:4];
                    not_drop <= csr_writedata[3];
                    user_crc <= csr_writedata[2];
                    tx_invert <= csr_writedata[1];
                    tx_push_pull <= csr_writedata[0];
                end
                REG_IDLE_WAIT_LEN:
                    idle_wait_len <= csr_writedata;
                REG_TX_PERMIT_LEN_L:
                    tx_permit_len <= {h_val_bkup[1:0], csr_writedata};
                REG_TX_PERMIT_LEN_H:
                    h_val_bkup <= csr_writedata;
                REG_MAX_IDLE_LEN_L:
                    max_idle_len <= {h_val_bkup[1:0], csr_writedata};
                REG_MAX_IDLE_LEN_H:
                    h_val_bkup <= csr_writedata;
                REG_TX_PRE_LEN:
                    tx_pre_len <= csr_writedata[1:0];
                REG_FILTER:
                    filter <= csr_writedata;
                REG_DIV_LS_L:
                    div_ls <= {h_val_bkup, csr_writedata};
                REG_DIV_LS_H:
                    h_val_bkup <= csr_writedata;
                REG_DIV_HS_L:
                    div_hs <= {h_val_bkup, csr_writedata};
                REG_DIV_HS_H:
                    h_val_bkup <= csr_writedata;
                REG_INT_MASK_L:
                    int_mask[7:0] <= csr_writedata;
                REG_INT_MASK_H:
                    int_mask[15:8] <= csr_writedata;
                REG_DAT: begin
                    tx_ram_wr_addr <= tx_ram_wr_addr + 1'd1;
`ifdef HAS_CHIP_SELECT
                    has_write_tx <= 1;
`endif
                end
                REG_CTRL: begin
                    if (csr_writedata[7])
                        rx_clean_all <= 1;
                    if (csr_writedata[4])
                        rx_ram_rd_done <= 1;
                    if (csr_writedata[3])
                        tx_abort <= 1;
                    if (csr_writedata[2])
                        tx_drop <= 1;
                    if (csr_writedata[1])
                        has_break <= 1;
                    if (csr_writedata[0])
                        tx_ram_wr_done <= 1;
`ifndef HAS_CHIP_SELECT
                    rx_ram_rd_addr <= 0;
                    tx_ram_wr_addr <= 0;
`endif
                end
                REG_FILTER_M0:
                    filter_m0 <= csr_writedata;
                REG_FILTER_M1:
                    filter_m1 <= csr_writedata;
            endcase
    end

endmodule

