/*
 * This Source Code Form is subject to the terms of the Mozilla
 * Public License, v. 2.0. If a copy of the MPL was not distributed
 * with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
 * Notice: The scope granted to MPL excludes the ASIC industry.
 *
 * Copyright (c) 2017 DUKELEC, All rights reserved.
 *
 * Author: Duke Fong <d@d-l.io>
 *
 * This file is the top module of CDBUS IP.
 */

module cdbus
    #(
        parameter DIV_LS = 346, // default: 115200 bps for 40MHz clk
        parameter DIV_HS = 346
    )(
        input               clk,
        input               reset_n,
        input               chip_select, // reduce ram_rx power consumption
        output              irq,

        input       [4:0]   csr_address,
        input               csr_read,
        output      [7:0]   csr_readdata,
        input               csr_write,
        input       [7:0]   csr_writedata,

        input               rx,
        output              tx,
        output              tx_en
    );

wire full_duplex;
wire break_sync;
wire arbitration;
wire not_drop;
wire user_crc;
wire tx_invert;
wire tx_push_pull;

wire [7:0] idle_wait_len;
wire [9:0] tx_permit_len;
wire [9:0] max_idle_len;
wire [1:0] tx_pre_len;
wire [7:0] filter;
wire [7:0] filter_m0;
wire [7:0] filter_m1;
wire [15:0] div_ls;
wire [15:0] div_hs;

wire [7:0] rx_ram_rd_addr;
wire rx_ram_rd_done;
wire rx_clean_all;
wire [7:0] rx_ram_rd_byte;
wire [7:0] rx_ram_rd_flags;
wire rx_error;
wire rx_ram_lost;
wire rx_break;
wire rx_pending;
wire bus_idle;

wire tx_ram_wr_en;
wire [7:0] tx_ram_wr_addr;
wire tx_ram_switch;
wire tx_abort;
wire has_break;
wire ack_break;
wire tx_pending;
wire cd;
wire tx_err;


wire [7:0] rx_ram_wr_byte;
wire [7:0] rx_ram_wr_addr;
wire rx_ram_wr_en;
wire rx_ram_switch;
wire [7:0] rx_ram_wr_flags;

wire [7:0] tx_ram_rd_byte;
wire [7:0] tx_ram_rd_addr;
wire tx_ram_rd_en;
wire tx_ram_rd_done;

wire [7:0] des_data;
wire [15:0] des_crc_data;
wire des_data_clk;
wire force_wait_idle;

wire [7:0] ser_data;
wire ser_has_data;
wire ser_ack_data;
wire ser_is_crc_byte;
wire ser_is_last_byte;
wire [15:0] ser_crc_data;


reg [1:0] rx_d;
always @(posedge clk)
    rx_d <= {rx_d[0], rx};

wire tx_d;
wire tx_en_d;
wire tx_may_invert = tx_invert ? ~tx_d : tx_d;

assign tx_en = (reset_n && tx_push_pull) ? tx_en_d : 1'bz;
assign tx = (reset_n && (tx_push_pull || !tx_may_invert)) ? tx_may_invert : 1'bz;


cd_csr #(
    .DIV_LS(DIV_LS),
    .DIV_HS(DIV_HS)
) cd_csr_m(
    .clk(clk),
    .reset_n(reset_n),
    .irq(irq),
`ifdef INT_FLAG_SNAPSHOT
    .int_flag_update(~chip_select),
`endif

    .csr_address(csr_address),
    .csr_read(csr_read),
    .csr_readdata(csr_readdata),
    .csr_write(csr_write),
    .csr_writedata(csr_writedata),

    .full_duplex(full_duplex),
    .break_sync(break_sync),
    .arbitration(arbitration),
    .not_drop(not_drop),
    .user_crc(user_crc),
    .tx_invert(tx_invert),
    .tx_push_pull(tx_push_pull),

    .idle_wait_len(idle_wait_len),
    .tx_permit_len(tx_permit_len),
    .max_idle_len(max_idle_len),
    .tx_pre_len(tx_pre_len),
    .filter(filter),
    .filter_m0(filter_m0),
    .filter_m1(filter_m1),
    .div_ls(div_ls),
    .div_hs(div_hs),

    .rx_ram_rd_addr(rx_ram_rd_addr),
    .rx_ram_rd_done(rx_ram_rd_done),
    .rx_clean_all(rx_clean_all),
    .rx_ram_rd_byte(rx_ram_rd_byte),
    .rx_ram_rd_flags(rx_ram_rd_flags),
    .rx_error(rx_error),
    .rx_ram_lost(rx_ram_lost),
    .rx_break(rx_break),
    .rx_pending(rx_pending),
    .bus_idle(bus_idle),

    .tx_ram_wr_en(tx_ram_wr_en),
    .tx_ram_wr_addr(tx_ram_wr_addr),
    .tx_ram_switch(tx_ram_switch),
    .tx_abort(tx_abort),
    .has_break(has_break),
    .ack_break(ack_break),
    .tx_pending(tx_pending),
    .cd(cd),
    .tx_err(tx_err)
);


cd_rx_ram cd_rx_ram_m(
    .clk(clk),
    .reset_n(reset_n),

    .rd_byte(rx_ram_rd_byte),
    .rd_addr(rx_ram_rd_addr),
    .rd_en(chip_select),
    .rd_done(rx_ram_rd_done),
    .rd_done_all(rx_clean_all),
    .unread(rx_pending),

    .wr_byte(rx_ram_wr_byte),
    .wr_addr(rx_ram_wr_addr),
    .wr_en(rx_ram_wr_en),

    .switch(rx_ram_switch),
    .wr_flags(rx_ram_wr_flags),
    .rd_flags(rx_ram_rd_flags),
    .switch_fail(rx_ram_lost)
);

cd_tx_ram cd_tx_ram_m(
    .clk(clk),
    .reset_n(reset_n),

    .rd_byte(tx_ram_rd_byte),
    .rd_addr(tx_ram_rd_addr),
    .rd_en(tx_ram_rd_en),
    .rd_done(tx_ram_rd_done),
    .unread(tx_pending),

    .wr_byte(csr_writedata),
    .wr_addr(tx_ram_wr_addr),
    .wr_en(tx_ram_wr_en),

    .switch(tx_ram_switch)
);

cd_rx_bytes cd_rx_bytes_m(
    .clk(clk),
    .reset_n(reset_n),

    .filter(filter),
    .filter_m0(filter_m0),
    .filter_m1(filter_m1),
    .user_crc(user_crc),
    .not_drop(not_drop),
    .abort(rx_clean_all),
    .error(rx_error),

    .des_bus_idle(bus_idle),
    .des_data(des_data),
    .des_crc_data(des_crc_data),
    .des_data_clk(des_data_clk),
    .des_force_wait_idle(force_wait_idle),

    .ram_wr_byte(rx_ram_wr_byte),
    .ram_wr_addr(rx_ram_wr_addr),
    .ram_wr_en(rx_ram_wr_en),
    .ram_wr_flags(rx_ram_wr_flags),
    .ram_switch(rx_ram_switch)
);

cd_rx_des cd_rx_des_m(
    .clk(clk),
    .reset_n(reset_n),

    .div_ls(div_ls),
    .div_hs(div_hs),
    .idle_wait_len(idle_wait_len),
    .bus_idle(bus_idle),
    .rx_break(rx_break),

    .force_wait_idle(force_wait_idle),

    .rx(rx_d[1]),

    .data(des_data),
    .crc_data(des_crc_data),
    .data_clk(des_data_clk)
);

cd_tx_bytes cd_tx_bytes_m(
    .clk(clk),
    .reset_n(reset_n),

    .user_crc(user_crc),
    .abort(tx_abort || tx_err),

    .data(ser_data),
    .has_data(ser_has_data),
    .ack_data(ser_ack_data),
    .is_crc_byte(ser_is_crc_byte),
    .is_last_byte(ser_is_last_byte),
    .crc_data(ser_crc_data),

    .ram_unread(tx_pending),
    .ram_rd_byte(tx_ram_rd_byte),
    .ram_rd_addr(tx_ram_rd_addr),
    .ram_rd_en(tx_ram_rd_en),
    .ram_rd_done(tx_ram_rd_done)
);

cd_tx_ser cd_tx_ser_m(
    .clk(clk),
    .reset_n(reset_n),

    .data(ser_data),
    .has_data(ser_has_data),
    .ack_data(ser_ack_data),
    .is_crc_byte(ser_is_crc_byte),
    .is_last_byte(ser_is_last_byte),
    .crc_data(ser_crc_data),
    .has_break(has_break),
    .ack_break(ack_break),

    .bus_idle(bus_idle),

    .div_ls(div_ls),
    .div_hs(div_hs),
    .tx_permit_len(tx_permit_len),
    .max_idle_len(max_idle_len),
    .tx_pre_len(tx_pre_len),
    .full_duplex(full_duplex),
    .break_sync(break_sync),
    .arbitration(arbitration),
    .abort(tx_abort),
    .cd(cd),
    .err(tx_err),

    .rx(rx_d[1]),
    .tx(tx_d),
    .tx_en(tx_en_d)
);

endmodule

