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

module rx_ser(
        input clk,
        input reset_n,

        input [15:0] period_ls, // low speed
        input [15:0] period_hs, // high speed
        input [7:0] idle_len,

        output wire bus_idle,

        input wait_bus_idle,

        input rx, // sync already

        output reg [7:0] data,
        output wire [15:0] crc_data,
        output reg data_clk
    );

reg [1:0] state;
localparam WAIT = 0, BUS_IDLE = 1, DATA = 2;
reg allow_data;
assign bus_idle = (state == BUS_IDLE);

reg [7:0] bit_cnt;
reg [15:0] period_cnt;
reg is_first_byte;
reg inside_byte;
wire [15:0] period_cur = (inside_byte && !is_first_byte) ? period_hs : period_ls;

reg crc_data_clk;
reg crc_clean;
reg crc_rx;

always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        data <= 0;
        data_clk <= 0;
        
        state <= WAIT;
        allow_data <= 0;
        
        bit_cnt <= 8'hff;
        period_cnt <= 0;
        is_first_byte <= 1;
        inside_byte <= 0;
        
        crc_data_clk <= 0;
        crc_clean <= 0;
        crc_rx <= 0;
    end
    else begin
        data_clk <= 0;
        crc_data_clk <= 0;
        crc_clean <= 0;
        crc_rx <= rx;
        
        period_cnt <= period_cnt + 1'd1;
        if (period_cnt >= period_cur) begin
            period_cnt <= 0;
            bit_cnt <= bit_cnt + 1'b1;
        end
        
        if (wait_bus_idle) begin
            bit_cnt <= 8'hff;
            allow_data <= 0;
            state <= WAIT;
        end
        else case (state)
            WAIT: begin
                if (rx == 0) begin
                    period_cnt <= 0;
                    if (allow_data) begin
                        bit_cnt <= 0;
                        inside_byte <= 1;
                        state <= DATA;
                    end
                    else begin
                        bit_cnt <= 8'hff;
                        is_first_byte <= 1;
                    end
                end
                else begin
                    if (period_cnt == period_cur) begin
                        inside_byte <= 0; // return to low rate at end of last bit
                    end
                    if (bit_cnt != 8'hff && bit_cnt >= idle_len) begin
                        is_first_byte <= 1;
                        state <= BUS_IDLE;
                    end
                end
            end

            BUS_IDLE: begin
                if (rx == 0) begin
                    period_cnt <= 0;
                    bit_cnt <= 0;
                    crc_clean <= 1; // prepare crc
                    inside_byte <= 1;
                    state <= DATA;
                end
            end

            DATA: begin
                if (period_cnt + 1 == {1'd0, period_cur[15:1]}) begin
                    if (bit_cnt == 0) begin
                        if (rx == 1) begin
                            bit_cnt <= 8'hff;
                            allow_data <= 0;
                            state <= WAIT;
                        end
                    end
                    else if (bit_cnt == 9) begin
                        if (rx == 0) begin
                            bit_cnt <= 8'hff;
                            allow_data <= 0;
                            state <= WAIT;
                        end
                        else begin
                            is_first_byte <= 0; // follow bytes use high speed rate
                            data_clk <= 1;
                            bit_cnt <= 8'hff;
                            allow_data <= 1;
                            state <= WAIT;
                        end
                    end
                    else begin // get data
                        data <= {rx, data[7:1]};
                        crc_data_clk <= 1'd1;
                    end
                end
            end
            
            default: state <= WAIT;
        endcase
    end

serial_crc rx_crc_m(
    .clk(clk),
    .reset_n(reset_n),
    .clean(crc_clean),
    .data_clk(crc_data_clk),
    .data_in(crc_rx),
    .crc_out(crc_data)
);

endmodule
