/*
 * This Source Code Form is subject to the terms of the Mozilla
 * Public License, v. 2.0. If a copy of the MPL was not distributed
 * with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
 * Notice: The scope granted to MPL excludes the ASIC industry.
 *
 * Copyright (c) 2017 DUKELEC, All rights reserved.
 *
 * Author: Duke Fong <duke@dukelec.com>
 */

module rx_des(
        input               clk,
        input               reset_n,

        input       [15:0]  div_ls, // low speed
        input       [15:0]  div_hs, // high speed
        input       [7:0]   idle_wait_len,

        output              bus_idle,
        output reg          bit_inc,

        input               force_wait_idle,

        input               rx, // sync already

        output reg  [7:0]   data,
        output      [15:0]  crc_data,
        output reg          data_clk
    );


// FSM

reg [2:0] state;
localparam
    WAIT        = 3'b001,
    BUS_IDLE    = 3'b010,
    DATA        = 3'b100;

reg allow_data;
assign bus_idle = (state == BUS_IDLE);

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        state <= WAIT;
        allow_data <= 0;
    end
    else begin

        case (state)
            WAIT: begin
                if (rx == 0 && allow_data)
                    state <= DATA;
                else if (idle_cnt >= idle_wait_len)
                    state <= BUS_IDLE;
            end

            BUS_IDLE: begin
                if (rx == 0)
                    state <= DATA;
            end

            DATA: begin
                if (data_clk) begin
                    state <= WAIT;
                    allow_data <= 1;
                end
            end
            
            default: state <= WAIT;
        endcase

        if (force_wait_idle || bit_err) begin
            state <= WAIT;
            allow_data <= 0;
        end

    end


// div_cnt

reg bit_mid;

reg is_first_byte;
reg hs_flag;

wire [15:0] div_cur = hs_flag ? div_hs : div_ls;
reg [15:0] div_cnt;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        div_cnt <= 0;
        bit_inc <= 0;
        bit_mid <= 0;
    end
    else begin
        bit_inc <= 0;
        bit_mid <= 0;

        if ((state != DATA && rx == 0) || bit_err) begin
            div_cnt <= 0;
        end
        else begin
            div_cnt <= div_cnt + 1'd1;

            if (div_cnt + 1'b1 == {1'd0, div_cur[15:1]})
                bit_mid <= 1;

            if (div_cnt >= div_cur) begin
                div_cnt <= 0;
                bit_inc <= 1;
            end
        end
    end


// idle_cnt

reg [7:0] idle_cnt;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        idle_cnt <= 0;
    end
    else begin
        if (state != WAIT || rx == 0)
            idle_cnt <= 0;
        else if (bit_inc)
            idle_cnt <= idle_cnt + 1'b1;
    end


// bits_ctrl

reg bit_err;

reg rx_d1;
reg rx_d2;

wire crc_rx = rx_d2;
reg crc_data_clk;

reg [3:0] bit_cnt; // range: [0, 9]

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        crc_data_clk <= 0;
        bit_err <= 0;
        data_clk <= 0;
        bit_cnt <= 0;
        rx_d1 <= 1;
        rx_d2 <= 1;
        data <= 0;
    end
    else begin
        crc_data_clk <= 0;
        bit_err <= 0;
        data_clk <= 0;
        rx_d1 <= rx;
        rx_d2 <= rx_d1;

        if (state != DATA) begin
            bit_cnt <= 0;
        end
        else if (bit_mid) begin

            bit_cnt <= bit_cnt + 1'd1;

            if (bit_cnt == 0) begin
                if (rx_d1 == 1)
                    bit_err <= 1;
            end
            else if (bit_cnt == 9) begin
                bit_cnt <= 0;

                if (rx_d1 == 0)
                    bit_err <= 1;
                else
                    data_clk <= 1;
            end
            else begin
                data <= {rx_d1, data[7:1]};
                crc_data_clk <= 1'd1;
            end
        end
    end


// hs_flag

reg byte_end;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        is_first_byte <= 1;
        hs_flag <= 0;
        byte_end <= 1;
    end
    else begin
        if (state == DATA)
            byte_end <= 0;

        if (data_clk) begin
            is_first_byte <= 0;
            byte_end <= 1;
        end

        if (force_wait_idle || bit_err) begin
            is_first_byte <= 1;
        end

        if (byte_end && bit_inc)
            hs_flag <= 0;
        if (state == WAIT && allow_data && rx == 0 && !is_first_byte)
            hs_flag <= 1;
        if (bit_err)
            hs_flag <= 0;
    end


serial_crc rx_crc_m(
    .clk(clk),
    .reset_n(reset_n),
    .clean(state == BUS_IDLE),
    .data_clk(crc_data_clk),
    .data_in(crc_rx),
    .crc_out(crc_data)
);

endmodule

