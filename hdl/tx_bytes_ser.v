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

module tx_bytes_ser (
        input               clk,
        input               reset_n,

        // control center
        input       [15:0]  div_ls, // low speed
        input       [15:0]  div_hs, // high speed
        input       [7:0]   tx_wait_len,
        input               user_crc,
        input               full_duplex,
        input               arbitrate,
        input       [1:0]   tx_en_delay,
        input               abort,
        output reg          cd,     // collision detect
        output reg          err,

        output reg          tx,
        output reg          tx_en,

        // pp_ram
        input               unread,
        input       [7:0]   data,
        output wire [7:0]   addr,
        output reg          read_done,

        // rx_des
        input               bus_idle,
        input               rx_bit_inc,

        input               rx
    );

reg [4:0] state;
localparam
    WAIT            = 5'b00001,
    DELAY_HEAD      = 5'b00010,
    DELAY_HEAD_END  = 5'b00100,
    DATA            = 5'b01000,
    DATA_END        = 5'b10000;

wire tx_busy = (state != WAIT);

reg hs_flag;

reg bit_inc;
reg bit_mid;

wire [15:0] div_cur = hs_flag ? div_hs : div_ls;
reg [15:0] div_cnt;

reg tx_permit_r;
wire tx_permit = tx_permit_r & (rx | full_duplex);
reg [7:0] tx_wait_cnt;

reg [1:0] delay_cnt;

reg is_crc_byte;
reg is_last_byte;
reg bit_finished;
reg crc_data_clk;
reg [7:0] tx_byte;
wire [9:0] tx_data = {1'b1, tx_byte, 1'b0};

reg byte_inc;

reg [3:0] bit_cnt; // range: [0, 9]
reg tx_en_dynamic;

wire [15:0] crc_data;

reg [8:0] byte_cnt;
assign addr = byte_cnt[7:0];
reg [7:0] data_len; // backup 3rd byte


// FSM

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        state <= WAIT;
    end
    else begin

        case (state)
        WAIT: begin
            if (tx_permit && unread)
                state <= arbitrate ? DATA : DELAY_HEAD;
        end

        DELAY_HEAD: begin
            if (delay_cnt == tx_en_delay)
                state <= DELAY_HEAD_END; // reset div_cnt
        end

        DELAY_HEAD_END: begin
            state <= DATA;
        end

        DATA: begin
            if (cd || err || (is_last_byte && byte_inc))
                state <= DATA_END;
        end

        DATA_END: begin // avoid send empty frame even when tx_permit is always true
            state <= WAIT;
        end

        default: state <= WAIT;
        endcase

        if (abort)
            state <= WAIT;
    end


// div_cnt

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        div_cnt <= 1;
        bit_inc <= 0;
        bit_mid <= 0;
    end
    else begin
        bit_inc <= 0;
        bit_mid <= 0;

        if ((state == WAIT && !full_duplex) || state == DELAY_HEAD_END) begin
            div_cnt <= 1;
        end
        else begin
            div_cnt <= div_cnt + 1'd1;

            if (div_cnt == div_cur - div_cur[15:2]) // at 3/4 position of bit
                bit_mid <= 1;

            if (div_cnt >= div_cur) begin
                div_cnt <= 0;
                bit_inc <= 1;
            end
        end
    end


// tx_permit

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        tx_wait_cnt <= 0;
        tx_permit_r <= 0;
    end
    else begin
        if (tx_wait_cnt >= tx_wait_len)
            tx_permit_r <= 1;

        if ((!bus_idle && !full_duplex) || tx_busy) begin
            tx_wait_cnt <= 0;
            tx_permit_r <= 0;
        end
        else if (full_duplex ? bit_inc : rx_bit_inc) begin
            tx_wait_cnt <= tx_wait_cnt + 1'b1;
        end
    end


// delay_cnt

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        delay_cnt <= 0;
    end
    else begin
        if (state == WAIT)
            delay_cnt <= 0;
        else if (bit_inc)
            delay_cnt <= delay_cnt + 1'b1;
    end


// bits_ctrl

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        hs_flag <= 0;
        crc_data_clk <= 0;
        cd <= 0;
        err <= 0;
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
        err <= 0;
        byte_inc <= 0;

        if (state != DATA) begin
            hs_flag <= 0;
            bit_cnt <= 0;
            tx <= 1;
            tx_en <= (state == DELAY_HEAD || state == DELAY_HEAD_END);
            bit_finished <= 0;
            tx_en_dynamic <= 1;
        end
        else if (!bit_finished) begin

            tx <= tx_data[bit_cnt];
            tx_en <= (tx_en_dynamic && tx_data[bit_cnt] && arbitrate) ? 0 : 1;

            if (tx_en_dynamic && arbitrate && bit_mid) begin
                cd <= tx && !rx;  // tx: 1, rx: 0
                err <= !tx && rx; // tx: 0, rx: 1
                if (rx == rx && bit_cnt == 9) begin
                    tx_en <= 1; // active tx_en
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

            if (abort) begin
                cd <= 0;
                err <= 0;
            end
        end
    end


// bytes_ctrl

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        byte_cnt <= 0;
        data_len <= 0;
        is_crc_byte <= 0;
        is_last_byte <= 0;
        tx_byte <= 0;
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

            // we have enough time to change the byte which send at second bit
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

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        read_done <= 0;
    end
    else begin
        read_done <= 0;
        if (err || abort || (is_last_byte && byte_inc))
            read_done <= 1;
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

