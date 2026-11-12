/*
 * This Source Code Form is subject to the terms of the CERN Open
 * Hardware Licence Version 2 - Strongly Reciprocal (CERN-OHL-S v2):
 * https://ohwr.org/cern_ohl_s_v2.txt (see the LICENSE file).
 * Notice: The CDBUS Exception (see the LICENSE_EXCEPTION file)
 * grants free commercial use in FPGAs and other programmable logic
 * devices; it does not extend to ASIC design or manufacturing.
 *
 * Copyright (c) 2017-2026 DUKELEC, All rights reserved.
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
        input       [7:0]   filter_msk0,
        input       [7:0]   filter_msk1,
        input               user_crc,
        input               not_drop,
        input               raw,        // transparent mode: no header, no crc check, pages of up to 255 bytes
        input               drop_echo,  // raw mode: drop own tx echo
        input               abort,
        output reg          error, // frame incomplete or crc error, not in raw mode

        // rx_des
        input               des_bus_idle,
        input       [7:0]   des_data,
        input               des_crc_eq_zero,
        input               des_data_clk,
        output reg          des_force_wait_idle,

        // pp_ram
        output      [7:0]   ram_wr_byte,
        output reg  [7:0]   ram_wr_addr,
        output reg          ram_wr_en,
        output      [7:0]   ram_wr_len,
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
reg is_data_too_long;
reg raw_cont;       // raw: the previous page was full, the frame goes on

// raw: byte count minus one, 0xff for an empty page
assign ram_wr_len = (raw && byte_cnt == 0) ? 8'hff : (not_drop || raw) ? ram_wr_addr : data_len;


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
                if (!des_bus_idle && !raw)
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
        ram_switch <= 0;

        byte_cnt <= 0;
        data_len <= 0;
        raw_cont <= 0;

        drop_flag <= 0;
        finish <= 0;
    end
    else begin
        error <= 0;
        ram_wr_en <= 0;
        ram_switch <= 0;
        finish <= 0;
        is_promiscuous <= (filter == 8'hff);
        is_data_too_long <= (data_len > (user_crc ? 8'd251 : 8'd253));

        if ((des_data & filter_msk0) == filter_m0 || (des_data & filter_msk1) == filter_m1)
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
                if (byte_cnt != 0 || raw_cont) begin
                    // raw: frame end; a single byte is noise, unless it follows a full page
                    if ((byte_cnt != 1 || raw_cont) && !drop_flag) begin
                        error <= !raw;
                        ram_switch <= raw || not_drop;
                        if (byte_cnt == 0) begin // raw: empty page; cd_rx_ram claims a block only at a write
                            ram_wr_addr <= 0;
                            ram_wr_en <= 1;
                        end
                    end
                    finish <= 1;
                    drop_flag <= 1; // avoid multi-clock ram_switch signal
                    raw_cont <= 0;
                end
            end

            // frame format: src_addr, dst_addr, data_len, [data], crc_l, crc_h
            else if (des_data_clk == 1) begin

                if (!byte_cnt[8]) begin
                    ram_wr_addr <= byte_cnt[7:0];
                    ram_wr_en <= 1;
                end

                // only set: raw mode, the echo flag must stay after tx is done
                if (byte_cnt == 0) begin
                    if (des_data == filter && !is_promiscuous)
                        drop_flag <= 1;
                end

                if (byte_cnt == 1) begin
                    if (des_data != filter && des_data != 8'hff && !is_multicast && !is_promiscuous)
                        drop_flag <= 1;
                end

                if (byte_cnt == 2) begin
                    data_len <= des_data;
                end

                if (!raw && byte_cnt == data_len + 5 - 1) begin // last byte
                    if (!drop_flag) begin
                        if ((des_crc_eq_zero || user_crc) && !is_data_too_long) begin
                            ram_switch <= 1;
                        end
                        else begin
                            error <= 1;
                            ram_switch <= not_drop;
                        end
                    end

                    finish <= 1;
                end

                if (raw && byte_cnt == 254) begin // page full, the frame goes on in the next page
                    ram_switch <= !drop_flag;
                    raw_cont <= !drop_flag;
                    finish <= 1;
                end

                byte_cnt <= byte_cnt + 1'd1;
            end

            if (raw && drop_echo)
                drop_flag <= 1;

            if (abort) begin
                error <= 0;
                ram_switch <= 0;
            end
        end

        if (abort)
            raw_cont <= 0;
    end

endmodule

