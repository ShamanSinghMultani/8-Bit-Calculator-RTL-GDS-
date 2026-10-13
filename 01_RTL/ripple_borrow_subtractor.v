//======================================================================
// ripple_borrow_subtractor.v
//----------------------------------------------------------------------
// WIDTH-bit subtractor built structurally from WIDTH full_subtractor
// cells. Computes diff = a - b - bin.
//
// bout = 1 means the subtraction underflowed, i.e. a < b. The divider
// uses exactly this bit as its "does the divisor fit?" comparison,
// which is why a borrow-based subtractor is used here rather than a
// two's-complement adder: the comparison comes out for free.
//======================================================================
`timescale 1ns / 1ps
`default_nettype none

module ripple_borrow_subtractor #(
    parameter integer WIDTH = 8
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire             bin,
    output wire [WIDTH-1:0] diff,
    output wire             bout
);

    // borrow[i] is the borrow going *into* stage i
    wire [WIDTH:0] borrow;
    assign borrow[0] = bin;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : g_fs
            full_subtractor u_fs (
                .a    (a[i]),
                .b    (b[i]),
                .bin  (borrow[i]),
                .diff (diff[i]),
                .bout (borrow[i+1])
            );
        end
    endgenerate

    assign bout = borrow[WIDTH];

endmodule

`default_nettype wire
