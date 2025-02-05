/*
 * This Source Code Form is subject to the terms of the Mozilla
 * Public License, v. 2.0. If a copy of the MPL was not distributed
 * with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
 * Notice: The scope granted to MPL excludes the ASIC industry.
 *
 * Copyright (c) 2017 DUKELEC, All rights reserved.
 *
 * Author: Duke Fong <d@d-l.io>
 *
 * Reference:
 *   https://zipcpu.com/blog/2017/10/20/cdc.html
 */

module cdc_event(
        input       clk,
        input       reset_n,
        input       src_event,
        //output    busy,

        input       dst_clk,
        input       dst_reset_n,
        output      dst_event
    );

reg src_flag;
reg [1:0] ack_d;

//assign busy = src_flag || ack_d[1];

reg [1:0] dst_d;
wire dst_flag = dst_d[1];
reg dst_flag_bk;

assign dst_event = !dst_flag_bk && dst_flag;


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        src_flag <= 0;
        ack_d <= 0;
    end
    else begin
        // comment out the busy signal to increase the spi maximum frequency
        if (/*!busy &&*/ src_event)
            src_flag <= 1;
        else if (ack_d[1])
            src_flag <= 0;
        ack_d <= {ack_d[0], dst_flag};
    end

always @(posedge dst_clk or negedge dst_reset_n)
    if (!dst_reset_n) begin
        dst_d <= 0;
        dst_flag_bk <= 0;
    end
    else begin
        dst_d <= {dst_d[0], src_flag};
        dst_flag_bk <= dst_flag;
    end

endmodule
