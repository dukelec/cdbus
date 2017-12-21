/*
 * This Source Code Form is subject to the terms of the Mozilla
 * Public License, v. 2.0. If a copy of the MPL was not distributed
 * with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
 * Notice: The scope granted to MPL excludes the ASIC industry.
 *
 * Copyright (c) 2017 DUKELEC, All rights reserved.
 *
 * Author: Duke Fong <duke@dukelec.com>
 *
 * This file is the top module of CDBUS IP.
 */

module cdbus
    #(
        parameter PERIOD_LS = 433,
        parameter PERIOD_HS = 433
    )(
        input       clk,
        input       reset_n,

        input       [4:0] csr_address,
        input       csr_read,
        output reg  [7:0] csr_readdata,
        input       csr_write,
        input       [7:0] csr_writedata,

        output      irq,

        input       rx,
        output      tx,
        output      tx_en
    );

localparam
    REG_VERSION       = 'h00,
    REG_SETTING       = 'h01,
    REG_IDLE_LEN      = 'h02,
    REG_TX_PERMIT_LEN = 'h03,
    REG_FILTER        = 'h04,
    REG_PERIOD_LS_L   = 'h05,
    REG_PERIOD_LS_H   = 'h06,
    REG_PERIOD_HS_L   = 'h07,
    REG_PERIOD_HS_H   = 'h08,
    REG_INT_FLAG      = 'h09,
    REG_INT_MASK      = 'h0a,
    REG_RX            = 'h0b,
    REG_TX            = 'h0c,
    REG_RX_CTRL       = 'h0d,
    REG_TX_CTRL       = 'h0e,
    REG_RX_ADDR       = 'h0f,
    REG_RX_PAGE_FLAG  = 'h10;

localparam VERSION   = 8'h03;

reg  arbitrate;
reg  [1:0] tx_en_extra_len;
reg  not_drop;
reg  user_crc;
reg  tx_invert;
reg  tx_push_pull;

reg  [7:0] idle_len;
reg  [7:0] tx_permit_len;
reg  [7:0] filter;
reg  [15:0] period_ls;    // low speed
reg  [15:0] period_hs;    // high speed

reg  cd_error_flag;
reg  cd_flag;
wire tx_pending;
reg  rx_error_flag;
reg  rx_lost_flag;
wire rx_pending;
wire bus_idle;

wire [6:0] int_flag = {cd_error_flag, cd_flag, ~tx_pending,
                       rx_error_flag, rx_lost_flag, rx_pending, bus_idle};
reg  [6:0] int_mask;

wire [7:0] rx_ram_rd_data;
reg  [7:0] rx_ram_rd_addr;
wire [7:0] rx_ram_rd_flags;
reg  rx_ram_rd_done;
reg  rx_ram_rd_done_all;

wire [7:0] tx_ram_wr_data = csr_writedata;
reg  [7:0] tx_ram_wr_addr;
wire tx_ram_wr_clk = (csr_address == REG_TX) ? csr_write : 1'b0;
reg  tx_ram_switch;


assign irq = (int_flag & int_mask) != 0;

reg  rx_d;
reg  rx_pipe;
always @(posedge clk)
    {rx_d, rx_pipe} <= {rx_pipe, rx};

wire cd;
wire cd_err;
wire tx_d;
wire tx_en_d;
wire tx_may_invert = tx_invert ? ~tx_d : tx_d;

assign tx_en = (reset_n && tx_push_pull) ? tx_en_d : 1'bz;
assign tx = (reset_n && (tx_push_pull || !tx_may_invert)) ? tx_may_invert : 1'bz;


always @(*)
    case (csr_address)
        REG_VERSION:
            csr_readdata = VERSION;
        REG_SETTING:
            csr_readdata = {1'b0, !arbitrate, tx_en_extra_len,
                            not_drop, user_crc, tx_invert, tx_push_pull};
        REG_IDLE_LEN:
            csr_readdata = idle_len;
        REG_TX_PERMIT_LEN:
            csr_readdata = tx_permit_len;
        REG_FILTER:
            csr_readdata = filter;
        REG_PERIOD_LS_L:
            csr_readdata = period_ls[7:0];
        REG_PERIOD_LS_H:
            csr_readdata = period_ls[15:8];
        REG_PERIOD_HS_L:
            csr_readdata = period_hs[7:0];
        REG_PERIOD_HS_H:
            csr_readdata = period_hs[15:8];
        REG_INT_FLAG:
            csr_readdata = {1'd0, int_flag};
        REG_INT_MASK:
            csr_readdata = {1'd0, int_mask};
        REG_RX:
            csr_readdata = rx_ram_rd_data;
        REG_RX_ADDR:
            csr_readdata = rx_ram_rd_addr;
        REG_RX_PAGE_FLAG:
            csr_readdata = rx_ram_rd_flags;
        default:
            csr_readdata = 0;
    endcase


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        arbitrate <= 1;
        tx_en_extra_len <= 1;
        not_drop <= 0;
        user_crc <= 0;
        tx_invert <= 0;
        tx_push_pull <= 0;
        
        idle_len <= 20;         // 2 byte (10 bits per byte)
        tx_permit_len <= 10;
        filter <= 8'hff;
        period_ls <= PERIOD_LS; // div = period+1
        period_hs <= PERIOD_HS;
        
        cd_error_flag <= 0;
        cd_flag <= 0;
        rx_error_flag <= 0;
        rx_lost_flag <= 0;
        
        int_mask <= 0;
        
        rx_ram_rd_addr <= 0;
        rx_ram_rd_done <= 0;
        rx_ram_rd_done_all <= 0;
        
        tx_ram_wr_addr <= 0;
        tx_ram_switch <= 0;
    end
    else begin
        rx_ram_rd_done <= 0;
        rx_ram_rd_done_all <= 0;
        tx_ram_switch <= 0;
        
        if (rx_error)
            rx_error_flag <= 1;
        if (rx_ram_lost)
            rx_lost_flag <= 1;
        if (cd)
            cd_flag <= 1;
        if (cd_err)
            cd_error_flag <= 1;

        if (csr_read && csr_address == REG_RX)
            rx_ram_rd_addr <= rx_ram_rd_addr + 1'd1;
        
        if (csr_write)
            case (csr_address)
                REG_SETTING: begin
                    arbitrate <= !csr_writedata[6];
                    tx_en_extra_len <= csr_writedata[5:4];
                    not_drop <= csr_writedata[3];
                    user_crc <= csr_writedata[2];
                    tx_invert <= csr_writedata[1];
                    tx_push_pull <= csr_writedata[0];
                end
                REG_IDLE_LEN:
                    idle_len <= csr_writedata;
                REG_TX_PERMIT_LEN:
                    tx_permit_len <= csr_writedata;
                REG_FILTER:
                    filter <= csr_writedata;
                REG_PERIOD_LS_L:
                    period_ls[7:0] <= csr_writedata;
                REG_PERIOD_LS_H:
                    period_ls[15:8] <= csr_writedata;
                REG_PERIOD_HS_L:
                    period_hs[7:0] <= csr_writedata;
                REG_PERIOD_HS_H:
                    period_hs[15:8] <= csr_writedata;
                REG_INT_MASK:
                    int_mask <= csr_writedata[6:0];
                REG_TX:
                    tx_ram_wr_addr <= tx_ram_wr_addr + 1'd1;
                REG_RX_CTRL: begin
                    if (csr_writedata[0])
                        rx_ram_rd_addr <= 0;
                    if (csr_writedata[1]) begin
                        rx_ram_rd_addr <= 0;
                        rx_ram_rd_done <= 1;
                    end
                    if (csr_writedata[2])
                        rx_lost_flag <= 0;
                    if (csr_writedata[3])
                        rx_error_flag <= 0;
                    if (csr_writedata[4]) begin
                        rx_ram_rd_addr <= 0;
                        rx_ram_rd_done_all <= 1;
                        rx_error_flag <= 0;
                        rx_lost_flag <= 0;
                    end
                end
                REG_TX_CTRL: begin
                    if (csr_writedata[0])
                        tx_ram_wr_addr <= 0;
                    if (csr_writedata[1]) begin
                        tx_ram_wr_addr <= 0;
                        tx_ram_switch <= 1;
                    end
                    if (csr_writedata[3])
                        cd_flag <= 0;
                    if (csr_writedata[4])
                        cd_error_flag <= 0;
                end
                REG_RX_ADDR: begin
                    rx_ram_rd_addr <= csr_writedata;
                end
            endcase
    end


wire [7:0] rx_ram_wr_data;
wire [7:0] rx_ram_wr_addr;
wire rx_ram_wr_clk;
wire rx_ram_switch;
wire [7:0] rx_ram_wr_flags;

pp_ram #(.N_WIDTH(3)) pp_ram_rx_m(
    .clk(clk),
    .reset_n(reset_n),
    
    .rd_byte(rx_ram_rd_data),
    .rd_addr(rx_ram_rd_addr),
    .rd_done(rx_ram_rd_done),
    .rd_done_all(rx_ram_rd_done_all),
    .unread(rx_pending),
    
    .wr_byte(rx_ram_wr_data),
    .wr_addr(rx_ram_wr_addr),
    .wr_clk(rx_ram_wr_clk),
    
    .switch(rx_ram_switch),
    .wr_flags(rx_ram_wr_flags),
    .rd_flags(rx_ram_rd_flags),
    .switch_fail(rx_ram_lost)
);

wire [7:0] tx_data;
wire [7:0] tx_addr;
wire tx_read_done;

pp_ram #(.N_WIDTH(1)) pp_ram_tx_m(
    .clk(clk),
    .reset_n(reset_n),
    
    .rd_byte(tx_data),
    .rd_addr(tx_addr),
    .rd_done(tx_read_done),
    .rd_done_all(1'b0),
    .unread(tx_pending),
    
    .wr_byte(tx_ram_wr_data),
    .wr_addr(tx_ram_wr_addr),
    .wr_clk(tx_ram_wr_clk),
    
    .switch(tx_ram_switch)
);

wire [7:0] ser_data;
wire [15:0] ser_crc_data;
wire ser_data_clk;
wire wait_bus_idle;

rx_bytes rx_bytes_m(
    .clk(clk),
    .reset_n(reset_n),
    
    .filter(filter),
    .user_crc(user_crc),
    .not_drop(not_drop),
    .abort(rx_ram_rd_done_all),
    .error(rx_error),
    
    .ser_bus_idle(bus_idle),
    .ser_data(ser_data),
    .ser_crc_data(ser_crc_data),
    .ser_data_clk(ser_data_clk),
    .ser_wait_bus_idle(wait_bus_idle),
    
    .wr_byte(rx_ram_wr_data),
    .wr_addr(rx_ram_wr_addr),
    .wr_clk(rx_ram_wr_clk),
    .wr_flags(rx_ram_wr_flags),
    .switch(rx_ram_switch)
);

rx_ser rx_ser_m(
    .clk(clk),
    .reset_n(reset_n),
    
    .period_ls(period_ls),
    .period_hs(period_hs),
    .idle_len(idle_len),
    
    .bus_idle(bus_idle),
    
    .wait_bus_idle(wait_bus_idle),
    
    .rx(rx_d),
    
    .data(ser_data),
    .crc_data(ser_crc_data),
    .data_clk(ser_data_clk)
);

tx_bytes_des tx_bytes_des_m(
    .clk(clk),
    .reset_n(reset_n),
    
    .period_ls(period_ls),
    .period_hs(period_hs),
    .user_crc(user_crc),
    
    .arbitrate(arbitrate),
    .tx_permit_len(tx_permit_len),
    .tx_en_extra_len(tx_en_extra_len),
    .cd(cd),
    .cd_err(cd_err),
    
    .tx(tx_d),
    .tx_en(tx_en_d),
    
    .unread(tx_pending),
    .data(tx_data),
    .addr(tx_addr),
    .read_done(tx_read_done),
    
    .bus_idle(bus_idle),
    .rx(rx_d)
);

endmodule
