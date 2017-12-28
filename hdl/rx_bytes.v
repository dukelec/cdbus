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

module rx_bytes (
        input               clk,
        input               reset_n,

        // control center
        input       [7:0]   filter,
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
        output wire [7:0]   wr_byte,
        output reg  [7:0]   wr_addr,
        output reg          wr_clk,
        output reg  [7:0]   wr_flags,
        output reg          switch
    );

assign wr_byte = des_data;


// FSM

reg [1:0] state;
localparam
    INIT    = 2'b01,
    DATA    = 2'b10;

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


//

reg [8:0] byte_cnt;
reg [7:0] data_len; // backup 3rd byte
reg drop_flag;
reg finish;
reg is_promiscuous;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        error <= 0;

        wr_addr <= 0;
        wr_clk <= 0;
        wr_flags <= 0;
        switch <= 0;

        byte_cnt <= 0;
        data_len <= 0;

        drop_flag <= 0;
        finish <= 0;
    end
    else begin
        error <= 0;
        wr_clk <= 0;
        switch <= 0;
        finish <= 0;
        is_promiscuous <= (filter == 8'hff);

        if (state == INIT) begin
            byte_cnt <= 0;
            data_len <= 0;
            drop_flag <= 0;
        end
        else begin

            if (des_bus_idle) begin
                if (byte_cnt != 0) begin
                    if ((byte_cnt != 1 && !drop_flag) || is_promiscuous) begin
                        error <= 1;
                        if (not_drop) begin
                            wr_flags <= byte_cnt[8] ? 8'hff : byte_cnt[7:0];
                            switch <= 1;
                        end
                    end
                    finish <= 1;
                    drop_flag <= 1; // avoid multi-clock switch signal
                end
            end

            // frame format: src_addr, dst_addr, data_len, [data], crc_l, crc_h
            else if (des_data_clk == 1) begin

                wr_addr <= byte_cnt[7:0];
                if (!byte_cnt[8])
                    wr_clk <= 1;

                if (byte_cnt == 0) begin
                    if (des_data == filter && !is_promiscuous)
                        drop_flag <= 1;
                end

                if (byte_cnt == 1) begin
                    if (des_data != filter && des_data != 8'hff && !is_promiscuous)
                        drop_flag <= 1;
                end

                if (byte_cnt == 2) begin
                    data_len <= des_data;
                end

                if (byte_cnt == data_len + 5 - 1) begin // last byte
                    if (!drop_flag) begin
                        if (des_crc_data == 0 || user_crc) begin
                            wr_flags <= 0; // 0: no error; else: rx length
                            switch <= 1;
                        end
                        else begin
                            error <= 1;
                            if (not_drop) begin
                                wr_flags <= byte_cnt[8] ? 8'hff : byte_cnt[7:0];
                                switch <= 1;
                            end
                        end
                    end

                    finish <= 1;
                end

                byte_cnt <= byte_cnt + 1'd1;
            end

            if (abort) begin
                error <= 0;
                switch <= 0;
            end
        end
    end

endmodule

