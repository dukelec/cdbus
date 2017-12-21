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
        input       clk,
        input       reset_n,

        // control center
        input       [15:0] period_ls, // low speed
        input       [15:0] period_hs, // high speed
        input       user_crc,
        input       arbitrate,
        input       [7:0] tx_permit_len,
        input       [1:0] tx_en_extra_len,
        output reg  cd,               // collision detection
        output reg  cd_err,

        output reg  tx,
        output reg  tx_en,

        // pp_ram
        input       unread,
        input       [7:0] data,
        output wire [7:0] addr,
        output reg  read_done,

        // rx_ser
        input       bus_idle,

        input       rx
    );

reg [2:0] state;
localparam
    WAIT_IDLE = 0,
    WAIT_PERMIT = 1,
    WAIT_BUFFER = 2,
    EN_ADVANCE = 3,
    DATA = 4,
    EN_DELAY = 5;

reg [8:0] byte_cnt;
reg [7:0] data_len; // backup 3rd byte
assign addr = byte_cnt[7:0];

reg [7:0]  bit_cnt;
reg [15:0] period_cnt;
reg [1:0]  retry_cnt;

wire [15:0] period_cur;
assign period_cur = (byte_cnt == 0) ? period_ls : period_hs;

//crc
reg crc_data_clk;
reg crc_clean;
wire [15:0] crc_data;


`ifdef TX_DATA_STATIC

reg [7:0] i_data;
wire [9:0] tx_data;
assign tx_data = {1'b1, i_data, 1'b0};

always @(crc_data, data, byte_cnt, data_len) begin
    if (byte_cnt == data_len + 3 && !user_crc) // does bit width need specify?
        i_data = crc_data[7:0];
    else if (byte_cnt == data_len + 4 && !user_crc)
        i_data = crc_data[15:8];
    else
        i_data = data;
end

`else

reg [9:0] tx_data;

// we have enough time to change the content which start at second bit
always @(posedge clk)
    if (byte_cnt == data_len + 3 && !user_crc)
        tx_data <= {1'b1, crc_data[7:0], 1'b0};
    else if (byte_cnt == data_len + 4 && !user_crc)
        tx_data <= {1'b1, crc_data[15:8], 1'b0};
    else
        tx_data <= {1'b1, data, 1'b0};
`endif


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        cd <= 0;
        cd_err <= 0;
        read_done <= 0;
        
        state <= WAIT_IDLE;
        
        byte_cnt <= 0;
        data_len <= 0;
        
        bit_cnt <= 0;
        period_cnt <= 0;
        retry_cnt <= 0;
        
        tx <= 1;
        tx_en <= 0;
        
        crc_data_clk <= 0;
        crc_clean <= 0;
    end
    else begin
        cd <= 0;
        cd_err <= 0;
        crc_data_clk <= 0;
        crc_clean <= 0;
        read_done <= 0;

        period_cnt <= period_cnt + 1'd1;
        if (period_cnt >= period_cur) begin
            period_cnt <= 0;
            bit_cnt <= bit_cnt + 1'b1;
        end
        
        case (state)

            WAIT_IDLE: begin
                tx <= 1;
                tx_en <= 0;
                if (bus_idle && rx == 1) begin
                    period_cnt <= 0;
                    bit_cnt <= 0;
                    byte_cnt <= 0;
                    state <= WAIT_PERMIT;
                end
            end
            
            WAIT_PERMIT: begin
                if (bus_idle && rx == 1) begin
                    if (bit_cnt == tx_permit_len)
                        state <= WAIT_BUFFER;
                end
                else begin
                    state <= WAIT_IDLE;
                end
            end

            WAIT_BUFFER: begin
                if (bus_idle && rx == 1) begin
                    if (unread) begin
                        period_cnt <= 0;
                        bit_cnt <= 0;
                        //byte_cnt <= 0;
                        data_len <= 0;
                        crc_clean <= 1;
                        state <= arbitrate ? DATA : EN_ADVANCE;
                    end
                end
                else begin
                    state <= WAIT_IDLE;
                end
            end
            
            EN_ADVANCE: begin
                tx_en <= 1;
                
                if (bit_cnt == tx_en_extra_len) begin
                    bit_cnt <= 0;
                    state <= DATA;
                end
            end

            DATA: begin
                if (period_cnt == 0) begin
                    tx <= tx_data[bit_cnt];
                    if (byte_cnt == 0 && tx_data[bit_cnt] == 1 && arbitrate)
                        tx_en <= 0;
                    else
                        tx_en <= 1;
                end
                else if (byte_cnt == 0 && period_cnt == {1'd0, period_cur[15:1]} && arbitrate) begin
                    if (tx == 1 && rx == 0) begin
                        cd <= 1;
                        state <= WAIT_IDLE;
                        if (retry_cnt == 2'b11) begin
                            read_done <= 1;
                            cd_err <= 1;
                            // retry_cnt would return to 0 for next transmission
                        end
                        retry_cnt <= retry_cnt + 1'd1;
                    end
                    else if (bit_cnt == 9) begin
                        retry_cnt <= 0;
                        tx_en <= 1; // advance 0.5 bit active tx_en
                    end
                end
                else if (period_cnt == period_cur) begin

                    if (bit_cnt != 0 && bit_cnt != 9 && byte_cnt < data_len + 3)
                        crc_data_clk <= 1;

                    if (bit_cnt == 9) begin
                        bit_cnt <= 0;
                        byte_cnt <= byte_cnt + 1'd1;
                    end

                    if (byte_cnt == 2 && bit_cnt == 0)
                        data_len <= data;
                    
                    if (byte_cnt == data_len + 5 - 1 && bit_cnt == 9) begin
                        state <= EN_DELAY;
                        byte_cnt <= 0;
                        bit_cnt <= 0;
                        read_done <= 1;
                    end
                end
            end
            
            EN_DELAY: begin
                if (bit_cnt == tx_en_extra_len)
                    state <= WAIT_IDLE;
            end
            
            default: state <= WAIT_IDLE;
        endcase
        
    end


serial_crc tx_crc_m(
    .clk(clk),
    .reset_n(reset_n),
    .clean(crc_clean),
    .data_clk(crc_data_clk),
    .data_in(tx),
    .crc_out(crc_data)
);

endmodule
