// Reference: http://zipcpu.com/blog/2017/10/20/cdc.html
// Collator: Duke Fong

module cdc_event(
        input clk,
        input reset_n,
        input src_event,
        output busy,
        
        input dst_clk,
        input dst_reset_n,
        output reg dst_event
    );

reg req;
reg ack;
reg xack_pipe;

assign busy = req || ack;

reg xreq_pipe;
reg new_req;
reg last_req;


always @(posedge clk or negedge reset_n)
    if (!reset_n) begin
        req <= 0;
        ack <= 0;
        xack_pipe <= 0;
    end
    else begin
        if (!busy && src_event)
            req <= 1;
        else if (ack)
            req <= 0;
        {ack, xack_pipe} <= {xack_pipe, new_req};
    end

always @(posedge dst_clk or negedge dst_reset_n)
    if (!dst_reset_n) begin
        xreq_pipe <= 0;
        new_req <= 0;
        last_req <= 0;
        dst_event <= 0;
    end
    else begin
        {last_req, new_req, xreq_pipe} <= {new_req, xreq_pipe, req};
        dst_event <= !last_req && new_req;
    end

endmodule
