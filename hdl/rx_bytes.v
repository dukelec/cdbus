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
        output reg          error, // crc error, data lost etc...

        // rx_ser
        input               ser_bus_idle,
        input       [7:0]   ser_data,
        input       [15:0]  ser_crc_data,
        input               ser_data_clk,
        output reg          ser_wait_bus_idle,

        // pp_ram
        output wire [7:0]   wr_byte,
        output reg  [7:0]   wr_addr,
        output reg          wr_clk,
        output reg  [7:0]   wr_flags,
        output reg          switch
    );

reg [8:0] byte_cnt;
reg [7:0] data_len; // backup 3rd byte
reg drop_flag;
assign wr_byte = ser_data;

reg state;
localparam NORMAL = 0, CLEANUP = 1;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        error <= 0;

        ser_wait_bus_idle <= 0;

        wr_addr <= 0;
        wr_clk <= 0;
        wr_flags <= 0;
        switch <= 0;

        byte_cnt <= 0;
        data_len <= 0;

        drop_flag <= 0;

        state <= NORMAL;
    end
    else begin
        error <= 0;
        ser_wait_bus_idle <= 0;
        wr_clk <= 0;
        switch <= 0;

        case (state)
            CLEANUP: begin
                ser_wait_bus_idle <= 1;
                byte_cnt <= 0;
                data_len <= 0;
                drop_flag <= 0;
                state <= NORMAL;
            end

            NORMAL: begin

                if (ser_bus_idle) begin
                    byte_cnt <= 0;
                    data_len <= 0;
                    if (byte_cnt != 0) begin
                        if (byte_cnt != 1 && !drop_flag) begin
                            error <= 1;
                            if (not_drop) begin
                                wr_flags <= byte_cnt[8] ? 8'hff : byte_cnt[7:0];
                                switch <= 1;
                            end
                        end
                        state <= CLEANUP;
                    end
                end

                // data format: src_addr, dst_addr, data_len, [data], crc_l, crc_h
                else if (ser_data_clk == 1) begin

                    wr_addr <= byte_cnt[7:0];
                    if (!byte_cnt[8])
                        wr_clk <= 1;

                    if (byte_cnt == 0) begin
                        if (ser_data == filter && filter != 8'hff)
                            drop_flag <= 1;
                    end

                    if (byte_cnt == 1) begin
                        if (ser_data != filter && ser_data != 8'hff && filter != 8'hff)
                            drop_flag <= 1;
                    end

                    if (byte_cnt == 2) begin
                        data_len <= ser_data;
                        //if (ser_data > 256 - 3) begin // data_len max 256-3 bytes
                        //    if (!drop_flag)
                        //        error <= 1;
                        //    state <= CLEANUP;
                        //end
                    end

                    if (byte_cnt == data_len + 5 - 1) begin // last byte (5 bytes except datas)
                        if (!drop_flag) begin
                            if (ser_crc_data == 0 || user_crc) begin
                                wr_flags <= 0; // 0: no error, else rx length
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
                        state <= CLEANUP;
                    end

                    byte_cnt <= byte_cnt + 1'd1;
                end
            end

            default: state <= CLEANUP;
        endcase

        if (abort) begin
            error <= 0;
            switch <= 0;
            state <= CLEANUP;
        end
    end

endmodule
