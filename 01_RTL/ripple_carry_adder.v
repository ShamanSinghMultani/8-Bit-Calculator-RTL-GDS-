//======================================================================
// ripple_carry_adder.v
//----------------------------------------------------------------------
// WIDTH-bit ripple-carry adder built structurally from WIDTH instances
// of full_adder. The carry chain is exposed as an internal bus so the
// critical path (cin -> cout through every stage) is explicit; this is
// the path that limits Fmax and shows up in the timing reports.
//======================================================================
`timescale 1ns / 1ps
`default_nettype none

module ripple_carry_adder #(
    parameter integer WIDTH = 8
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire             cin,
    output wire [WIDTH-1:0] sum,
    output wire             cout
);

    // carry[i] is the carry going *into* stage i
    wire [WIDTH:0] carry;
    assign carry[0] = cin;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : g_fa
            full_adder u_fa (
                .a    (a[i]),
                .b    (b[i]),
                .cin  (carry[i]),
                .sum  (sum[i]),
                .cout (carry[i+1])
            );
        end
    endgenerate

    assign cout = carry[WIDTH];

endmodule

`default_nettype wire
