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

module cd_rx_bytes(
        input               clk,
        input               reset_n,

        // cd_csr
        input       [7:0]   filter,
        input       [7:0]   filter_m0,
        input       [7:0]   filter_m1,
        input               user_crc,
        input               not_drop,
        input               abort,
        output reg          error, // frame incomplete or crc error

        // rx_des
        input               des_bus_idle,
        input       [7:0]   des_data,
        input       [15:0]  des_crc_data,
        input               des_data_clk,
        output reg          des_force_wait_idle,

        // pp_ram
        output wire [7:0]   ram_wr_byte,
        output reg  [7:0]   ram_wr_addr,
        output reg          ram_wr_en,
        output reg  [7:0]   ram_wr_flags,
        output reg          ram_switch
    );

assign ram_wr_byte = des_data;

reg state;
localparam
    INIT    = 1'b0,
    DATA    = 1'b1;

reg [8:0] byte_cnt;
reg [7:0] data_len; // backup 3rd byte
reg drop_flag;
reg finish;
reg is_promiscuous;
reg is_multicast;


// FSM

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        state <= INIT;
        des_force_wait_idle <= 0;
    end
    else begin
        des_force_wait_idle <= 0;

        case (state)
            INIT: begin
                if (!des_bus_idle)
                    des_force_wait_idle <= 1;
                state <= DATA;
            end

            DATA: begin
                if (finish)
                    state <= INIT;
            end

            default: state <= INIT;
        endcase

        if (abort)
            state <= INIT;
    end


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        error <= 0;

        ram_wr_addr <= 0;
        ram_wr_en <= 0;
        ram_wr_flags <= 0;
        ram_switch <= 0;

        byte_cnt <= 0;
        data_len <= 0;

        drop_flag <= 0;
        finish <= 0;
    end
    else begin
        error <= 0;
        ram_wr_en <= 0;
        ram_switch <= 0;
        finish <= 0;
        is_promiscuous <= (filter == 8'hff);

        if (des_data == filter_m0 || des_data == filter_m1)
            is_multicast <= 1;
        else
            is_multicast <= 0;

        if (state == INIT) begin
            byte_cnt <= 0;
            data_len <= 0;
            drop_flag <= 0;
        end
        else begin

            if (des_bus_idle) begin
                if (byte_cnt != 0) begin
                    if (byte_cnt != 1 && !drop_flag) begin
                        error <= 1;
                        if (not_drop) begin
                            ram_wr_flags <= ram_wr_addr;
                            ram_switch <= 1;
                        end
                    end
                    finish <= 1;
                    drop_flag <= 1; // avoid multi-clock ram_switch signal
                end
            end

            // frame format: src_addr, dst_addr, data_len, [data], crc_l, crc_h
            else if (des_data_clk == 1) begin

                if (!byte_cnt[8]) begin
                    ram_wr_addr <= byte_cnt[7:0];
                    ram_wr_en <= 1;
                end

                if (byte_cnt == 0) begin
                    if (des_data == filter)
                        drop_flag <= ~is_promiscuous;
                end

                if (byte_cnt == 1) begin
                    if (des_data != filter && des_data != 8'hff && !is_multicast)
                        drop_flag <= ~is_promiscuous;
                end

                if (byte_cnt == 2) begin
                    data_len <= des_data;
                end

                if (byte_cnt == data_len + 5 - 1) begin // last byte
                    if (!drop_flag) begin
                        if (des_crc_data == 0 || user_crc) begin
                            ram_wr_flags <= 0; // 0: no error; else: rx length
                            ram_switch <= 1;
                        end
                        else begin
                            error <= 1;
                            if (not_drop) begin
                                ram_wr_flags <= byte_cnt[8] ? 8'hff : byte_cnt[7:0];
                                ram_switch <= 1;
                            end
                        end
                    end

                    finish <= 1;
                end

                byte_cnt <= byte_cnt + 1'd1;
            end

            if (abort) begin
                error <= 0;
                ram_switch <= 0;
            end
        end
    end

endmodule

