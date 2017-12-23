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

module tx_bytes_des (
        input               clk,
        input               reset_n,

        // control center
        input       [15:0]  period_ls,  // low speed
        input       [15:0]  period_hs,  // high speed
        input               user_crc,
        input               arbitrate,
        input       [7:0]   tx_permit_len,
        input       [1:0]   tx_en_extra_head,
        input       [1:0]   tx_en_extra_tail,
        output reg          cd,         // collision detection
        output reg          cd_err,

        output reg          tx,
        output reg          tx_en,

        // pp_ram
        input               unread,
        input       [7:0]   data,
        output wire [7:0]   addr,
        output reg          read_done,

        // rx_ser
        input               tx_permit,

        input               rx
    );

wire tx_ready = tx_permit & unread;


// FSM

reg [1:0] extra_cnt;

reg [3:0] state;
localparam
    WAIT        = 4'b0001,
    EXTRA_HEAD  = 4'b0010,
    DATA        = 4'b0100,
    EXTRA_TAIL  = 4'b1000;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        state <= WAIT;
    end
    else begin

        case (state)
        WAIT: begin
            if (tx_permit && unread)
                state <= arbitrate ? DATA : EXTRA_HEAD;
        end

        EXTRA_HEAD: begin
            if (extra_cnt == tx_en_extra_head)
                state <= DATA;
        end

        DATA: begin
            if (cd)
                state <= WAIT;
            else if (read_done)
                state <= EXTRA_TAIL;
        end

        EXTRA_TAIL: begin
            if (extra_cnt == tx_en_extra_tail)
                state <= WAIT;
        end

        default: state <= WAIT;

        endcase
    end


// period_cnt

reg hs_flag; // belongs to bits_ctrl

reg bit_inc;
reg bit_mid;

wire [15:0] period_cur = hs_flag ? period_hs : period_ls;
reg [15:0] period_cnt;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        period_cnt <= 0;
        bit_inc <= 0;
        bit_mid <= 0;
    end
    else begin
        bit_inc <= 0;
        bit_mid <= 0;

        if (state == WAIT) begin
            period_cnt <= 0;
        end
        else begin
            period_cnt <= period_cnt + 1'd1;

            if (period_cnt == {1'd0, period_cur[15:1]})
                bit_mid <= 1;

            if (period_cnt >= period_cur) begin
                period_cnt <= 0;
                bit_inc <= 1;
            end
        end
    end


// extra_cnt

reg bit_finished;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        extra_cnt <= 0;
    end
    else begin
        if (state == WAIT || state == DATA)
            extra_cnt <= 0;
        else if (bit_inc && !bit_finished)
            extra_cnt <= extra_cnt + 1'b1;
    end


// bits_ctrl

reg is_crc_byte;
reg is_last_byte;
reg crc_data_clk;
reg [7:0] tx_byte; // belongs to bytes_ctrl
wire [9:0] tx_data = {1'b1, tx_byte, 1'b0};

reg byte_inc;

reg [3:0] bit_cnt; // range: [0, 9]
reg tx_en_dynamic;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        hs_flag <= 0;
        crc_data_clk <= 0;
        cd <= 0;
        byte_inc <= 0;
        bit_cnt <= 0;
        bit_finished <= 0;
        tx_en_dynamic <= 1;

        tx <= 1;
        tx_en <= 0;
    end
    else begin
        crc_data_clk <= 0;
        cd <= 0;
        byte_inc <= 0;

        if (state != DATA) begin
            hs_flag <= 0;
            bit_cnt <= 0;
            tx <= 1;
            tx_en <= (state == EXTRA_HEAD || state == EXTRA_TAIL);
            bit_finished <= 0;
            tx_en_dynamic <= 1;
        end
        else if (!bit_finished) begin

            tx <= tx_data[bit_cnt];
            tx_en <= (tx_en_dynamic && tx_data[bit_cnt] && arbitrate) ? 0 : 1;

            if (tx_en_dynamic && arbitrate && bit_mid) begin
                if (tx && !rx)
                    cd <= 1;
                else if (bit_cnt == 9) begin
                    tx_en <= 1; // advance 0.5 bit active tx_en
                    tx_en_dynamic <= 0;
                end
            end

            if (bit_inc) begin
                crc_data_clk <= (bit_cnt != 0 && bit_cnt != 9 && !is_crc_byte) ? 1 : 0;
                bit_cnt <= bit_cnt + 1'd1;
                if (bit_cnt == 9) begin
                    hs_flag <= 1;
                    bit_cnt <= 0;
                    byte_inc <= 1;
                    if (is_last_byte)
                        bit_finished <= 1;
                end
            end
        end
    end


// bytes_ctrl

wire [15:0] crc_data;

reg [8:0] byte_cnt;
assign addr = byte_cnt[7:0];
reg [7:0] data_len; // backup 3rd byte

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        byte_cnt <= 0;
        data_len <= 0;
        is_crc_byte <= 0;
        is_last_byte <= 0;
    end
    else begin

        if (state != DATA) begin
            byte_cnt <= 0;
            data_len <= 0;
            is_crc_byte <= 0;
            is_last_byte <= 0;
        end
        else begin

            tx_byte <= data;

            if (byte_cnt == 2)
                data_len <= data;

            // we have enough time to change the content which start at second bit
            else if (byte_cnt == data_len + 3) begin
                if (!user_crc)
                    tx_byte <= crc_data[7:0];
                is_crc_byte <= 1;
            end
            else if (byte_cnt == data_len + 4) begin
                if (!user_crc)
                    tx_byte <= crc_data[15:8];
                is_last_byte <= 1;
            end

            if (byte_inc)
                byte_cnt <= byte_cnt + 1'd1;
        end
    end


// cd_err and read_done

reg [1:0] retry_cnt;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        retry_cnt <= 0;
        read_done <= 0;
        cd_err <= 0;
    end
    else begin
        read_done <= 0;
        cd_err <= 0;

        if (cd) begin
            retry_cnt <= retry_cnt + 1'd1;
            if (retry_cnt == 2'b11) begin
                read_done <= 1;
                cd_err <= 1;
                // retry_cnt would return to 0 for next transmission
            end
        end
        else if (is_last_byte && byte_inc) begin
            read_done <= 1;
        end
    end


serial_crc tx_crc_m(
    .clk(clk),
    .reset_n(reset_n),
    .clean(state != DATA),
    .data_clk(crc_data_clk),
    .data_in(tx),
    .crc_out(crc_data)
);

endmodule
