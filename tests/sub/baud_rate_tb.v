`timescale 1 ns / 1 ps

`define frequency 25000000 //(Hz)
`define cycle (1000000000.0/`frequency) //clock period (nS)


module baud_rate_tb;

reg clk;
reg sync;
reg sel;
wire [1:0] cnt;

initial
begin
    clk = 0;
    sync = 0;
    sel = 0;
    #901;
    sync = 1;
    #`cycle;
    sync = 0;
    #10000;
    sel = 1;
    #2000000;
    $finish;
end

always #(`cycle/2.0) clk = ~clk;


baud_rate #(.FOR_TX(1)) baud_rate_m(
    .clk(clk),
    .sync(sync),
    .div_ls(16'b00101),
    .div_hs(16'b10100),
    .sel(sel),
    .inc(inc),
    .cap(cap)
);

initial begin
    $dumpfile("baud_rate.vcd");
    $dumpvars();
end

endmodule
