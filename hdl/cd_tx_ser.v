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

module cd_tx_ser(
        input               clk,
        input               reset_n,

        input       [7:0]   data,
        input               has_data,
        output reg          ack_data,
        input               is_crc_byte,
        input               is_last_byte,
        output      [15:0]  crc_data,
        input               has_break,
        output reg          ack_break,

        input               bus_idle, // from rx_des

        input       [15:0]  div_ls,
        input       [15:0]  div_hs,
        input       [9:0]   tx_permit_len,
        input       [9:0]   max_idle_len,
        input       [1:0]   tx_pre_len,
        input               full_duplex,
        input               break_sync,
        input               arbitration,
        input               abort,
        output reg          cd, // collision detect
        output reg          err,

        input               rx,
        output reg          tx,
        output reg          tx_en
    );

reg [2:0] state;
localparam
    WAIT            = 3'b001,
    TX_PRE          = 3'b010,
    DATA            = 3'b100;

reg [1:0] tx_permit_d;
always @(posedge clk) tx_permit_d[1] <= tx_permit_d[0];
wire tx_permit = break_sync ? (tx_permit_d == 2'b01) : tx_permit_d[0];
reg reach_max_idle;
reg [9:0] tx_wait_cnt;
reg [1:0] delay_cnt;

reg is_break;
wire [9:0] tx_data = is_break ? 10'd0 : {1'b1, data, 1'b0};

reg [3:0] bit_cnt; // range: [0, 9]
reg arbitration_field;

reg crc_clk;

reg baud_sync;
reg baud_sel;
wire bit_inc;
wire bit_cap;


// FSM

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        state <= WAIT;
        is_break <= 0;
    end
    else begin
        baud_sync <= 0;

        case (state)
        WAIT: begin
            baud_sel <= 0;
            if ((!full_duplex && !bus_idle) || reach_max_idle)
                baud_sync <= 1;

            if (tx_permit && (has_data || has_break)) begin
                is_break <= has_break;
                state <= arbitration ? DATA : TX_PRE;
                baud_sync <= 1;
            end
            else if (break_sync && reach_max_idle && has_data) begin
                is_break <= 1;
                state <= DATA;
            end
        end

        TX_PRE: begin
            if (delay_cnt == tx_pre_len) begin
                state <= DATA;
                baud_sync <= 1;
            end
        end

        DATA: begin
            if (cd || err || (!has_data && !is_break))
                state <= WAIT;

            if (ack_data)
                baud_sel <= 1;
            if (ack_break) begin
                is_break <= 0;
                state <= WAIT;
            end
        end

        default: state <= WAIT;
        endcase

        if (abort)
            state <= WAIT;
    end


// tx_wait_cnt

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        tx_permit_d[0] <= 0;
    end
    else begin
        if ((!bus_idle && !full_duplex) || state != WAIT) begin
            tx_wait_cnt <= 0;
            tx_permit_d[0] <= 0;
            reach_max_idle <= 0;
        end
        else if (bit_inc) begin
            tx_wait_cnt <= tx_wait_cnt + 1'b1;
            if (tx_wait_cnt >= tx_permit_len)
                tx_permit_d[0] <= 1;
            if (tx_wait_cnt >= max_idle_len)
                reach_max_idle <= 1;
        end
    end


// delay_cnt

always @(posedge clk) begin
    if (state == WAIT)
        delay_cnt <= 0;
    else if (bit_inc)
        delay_cnt <= delay_cnt + 1'b1;
end


// bits_ctrl

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        crc_clk <= 0;
        cd <= 0;
        err <= 0;
        ack_data <= 0;
        ack_break <= 0;
        bit_cnt <= 0;
        arbitration_field <= 1;

        tx <= 1;
        tx_en <= 0;
    end
    else begin
        crc_clk <= 0;
        cd <= 0;
        err <= 0;
        ack_data <= 0;
        ack_break <= 0;

        if (state != DATA) begin
            bit_cnt <= 0;
            tx <= 1;
            tx_en <= (state == TX_PRE);
            arbitration_field <= 1;
        end
        else begin

            tx <= tx_data[bit_cnt];
            tx_en <= (arbitration_field && tx_data[bit_cnt] && arbitration) ? 0 : 1;

            if (arbitration_field && arbitration && bit_cap) begin
                cd <= tx && !rx;  // tx: 1, rx: 0
                err <= !tx && rx; // tx: 0, rx: 1
                if (tx == rx && bit_cnt == 9)
                    arbitration_field <= 0;
            end

            if (bit_inc) begin
                crc_clk <= (bit_cnt != 0 && bit_cnt != 9 && !is_break) ? 1 : 0;
                bit_cnt <= bit_cnt + 1'd1;
                if (bit_cnt == 9) begin
                    bit_cnt <= 0;
                    if (is_break) begin
                        ack_break <= 1;
                        bit_cnt <= 9; // tx remains 1 before exiting DATA state
                    end
                    else begin
                        ack_data <= 1;
                        if (is_last_byte)
                            bit_cnt <= 9;
                    end
                end
            end

            if (abort) begin
                cd <= 0;
                err <= 0;
            end
        end
    end


cd_baud_rate #(
    .INIT_VAL(2),
    .FOR_TX(1)
) cd_baud_rate_tx_m(
    .clk(clk),
    .sync(baud_sync),
    .sync_3x(1'b0),
    .div_ls(div_ls),
    .div_hs(div_hs),
    .sel(baud_sel),
    .inc(bit_inc),
    .cap(bit_cap)
);

cd_crc cd_crc_tx_m(
    .clk(clk),
    .clean(state == WAIT),
    .data_clk(!is_crc_byte && crc_clk),
    .data_in(tx),
    .crc_out(crc_data)
);

endmodule

