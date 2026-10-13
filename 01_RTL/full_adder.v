//======================================================================
// full_adder.v
//----------------------------------------------------------------------
// 1-bit full adder, described at gate level (structural / dataflow).
// This is the fundamental building block of the entire datapath:
// the ripple-carry adder, the array multiplier and the divider's
// compare-subtract step are all built from arrays of this cell.
//
//   sum  = a XOR b XOR cin
//   cout = majority(a, b, cin)
//======================================================================
`timescale 1ns / 1ps
`default_nettype none

module full_adder (
    input  wire a,      // operand bit A
    input  wire b,      // operand bit B
    input  wire cin,    // carry in
    output wire sum,    // sum bit
    output wire cout    // carry out
);

    assign sum  = a ^ b ^ cin;
    assign cout = (a & b) | (b & cin) | (a & cin);

endmodule

`default_nettype wire
