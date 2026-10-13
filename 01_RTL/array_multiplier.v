//======================================================================
// array_multiplier.v
//----------------------------------------------------------------------
// WIDTH x WIDTH -> 2*WIDTH unsigned array multiplier, built structurally
// from ripple_carry_adder rows (and therefore, ultimately, from
// full_adder cells).
//
// Algorithm (classic shift-and-add array, fully combinational):
//   1. Form WIDTH partial products  pp[i] = a & {WIDTH{b[i]}}
//   2. Row i adds pp[i] to the shifted running sum from row i-1.
//   3. The LSB falling out of each row is a final product bit.
//
// Row i produces product[i]; the last row's carry+sum form the upper
// half of the product. Purely combinational: WIDTH-1 adder rows deep,
// which is the longest path in the whole calculator.
//======================================================================
`timescale 1ns / 1ps
`default_nettype none

module array_multiplier #(
    parameter integer WIDTH = 8
)(
    input  wire [WIDTH-1:0]   a,
    input  wire [WIDTH-1:0]   b,
    output wire [2*WIDTH-1:0] product
);

    // ---- Stage 1: partial products -----------------------------------
    // pp[i] = a AND b[i]  (an AND-gate array, WIDTH*WIDTH gates)
    wire [WIDTH-1:0] pp [0:WIDTH-1];

    genvar i, j;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : g_pp
            for (j = 0; j < WIDTH; j = j + 1) begin : g_pp_bit
                assign pp[i][j] = a[j] & b[i];
            end
        end
    endgenerate

    // ---- Stage 2: accumulation rows ----------------------------------
    // rsum[i] / rcout[i] hold the running partial sum after row i.
    // Row 0 is trivial (nothing to add yet) so rows run from 1..WIDTH-1.
    wire [WIDTH-1:0] rsum  [0:WIDTH-1];
    wire             rcout [0:WIDTH-1];

    // Row 0: no addition, just pass the first partial product through.
    assign rsum[0]  = pp[0];
    assign rcout[0] = 1'b0;

    // product[0] comes straight out of row 0.
    assign product[0] = pp[0][0];

    generate
        for (i = 1; i < WIDTH; i = i + 1) begin : g_row
            // Left operand: previous row's sum shifted right by one
            // (the bit already emitted as product[i-1] is dropped, and
            //  the previous carry-out fills the new MSB).
            wire [WIDTH-1:0] shifted;
            assign shifted = {rcout[i-1], rsum[i-1][WIDTH-1:1]};

            ripple_carry_adder #(.WIDTH(WIDTH)) u_row (
                .a    (shifted),
                .b    (pp[i]),
                .cin  (1'b0),
                .sum  (rsum[i]),
                .cout (rcout[i])
            );

            // LSB of every row is a finished product bit.
            assign product[i] = rsum[i][0];
        end
    endgenerate

    // ---- Stage 3: upper half of the product --------------------------
    assign product[2*WIDTH-1:WIDTH] = {rcout[WIDTH-1], rsum[WIDTH-1][WIDTH-1:1]};

endmodule

`default_nettype wire
