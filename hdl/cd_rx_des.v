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

module cd_rx_des(
        input               clk,
        input               reset_n,

        input       [15:0]  div_ls,
        input       [15:0]  div_hs,
        input       [7:0]   idle_wait_len,
        output              bus_idle,
        output reg          rx_break,

        input               force_wait_idle,

        input               rx, // already sync

        output reg  [7:0]   data,
        output      [15:0]  crc_data,
        output reg          data_clk
    );

localparam
    WAIT_IDLE   = 4'b0001,
    WAIT_DATA   = 4'b0010,
    BUS_IDLE    = 4'b0100,
    DATA        = 4'b1000;

reg [3:0] state;
assign bus_idle = (state == BUS_IDLE);

reg [7:0] idle_cnt;
reg [3:0] bit_cnt; // range: [0, 9]
reg bit_err;

reg [1:0] rx_d;
always @(posedge clk) rx_d <= {rx_d[0], rx};

reg crc_clk;

reg is_first_byte;
reg baud_sync;
reg baud_sync_3x; // compensate for 3x oversampling
reg baud_sel;
wire bit_inc;
wire bit_cap;


// FSM

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        state <= WAIT_IDLE;
    end
    else begin
        baud_sync <= 0;
        baud_sync_3x <= 0;

        case (state)
            WAIT_IDLE: begin
                baud_sel <= 0;
                is_first_byte <= 1;
                if (idle_cnt >= idle_wait_len) begin
                    state <= BUS_IDLE;
                end
            end

            WAIT_DATA: begin
                if (rx == 0) begin
                    state <= DATA;
                    baud_sel <= !is_first_byte;
                end
                else if (idle_cnt >= idle_wait_len) begin
                    state <= BUS_IDLE;
                end
            end

            BUS_IDLE: begin
                baud_sel <= 0;
                is_first_byte <= 1;
                baud_sync <= 1;

                if (rx == 0) begin
                    state <= DATA;
                    baud_sync <= 0;
                end
            end

            DATA: begin
                // triggered simultaneously with data_clk
                if (bit_cap && bit_cnt == 9 && rx_d[0] == 1) begin
                    if (rx == 1) begin
                        state <= WAIT_DATA;
                        baud_sel <= 0;
                        baud_sync <= 1;
                    end
                    else begin // faster than expected
                        baud_sel <= 1;
                        baud_sync_3x <= 1;
                    end
                    is_first_byte <= 0;
                end
            end

            default: state <= WAIT_IDLE;
        endcase

        if (force_wait_idle || bit_err || rx_break)
            state <= WAIT_IDLE;
    end


// idle_cnt

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        idle_cnt <= 0;
    end
    else begin
        if (state == DATA || rx == 0)
            idle_cnt <= 0;
        else if (bit_inc)
            idle_cnt <= idle_cnt + 1'b1;
    end


// bits_ctrl

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        crc_clk <= 0;
        bit_err <= 0;
        rx_break <= 0;
        data_clk <= 0;
        bit_cnt <= 0;
    end
    else begin
        crc_clk <= 0;
        bit_err <= 0;
        rx_break <= 0;
        data_clk <= 0;

        if (state != DATA) begin
            bit_cnt <= 0;
        end
        else if (bit_cap) begin

            bit_cnt <= bit_cnt + 1'd1;

            if (bit_cnt == 0) begin
                if (rx_d[0] == 1)
                    bit_err <= 1;
            end
            else if (bit_cnt == 9) begin
                bit_cnt <= 0;

                if (rx_d[0] == 0) begin
                    if (data == 0)
                        rx_break <= 1;
                    else
                        bit_err <= 1;
                end
                else begin
                    data_clk <= 1;
                end
            end
            else begin
                data <= {rx_d[0], data[7:1]};
                crc_clk <= 1'd1;
            end
        end
    end


cd_baud_rate #(
    .INIT_VAL(1)
) cd_baud_rate_rx_m(
    .clk(clk),
    .sync(baud_sync || (state == WAIT_DATA && rx == 0)),
    .sync_3x(baud_sync_3x),
    .div_ls(div_ls),
    .div_hs(div_hs),
    .sel(baud_sel),
    .inc(bit_inc),
    .cap(bit_cap)
);

cd_crc cd_crc_rx_m(
    .clk(clk),
    .clean(state == BUS_IDLE),
    .data_clk(crc_clk),
    .data_in(rx_d[1]),
    .crc_out(crc_data)
);

endmodule

