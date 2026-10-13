//======================================================================
// full_subtractor.v
//----------------------------------------------------------------------
// 1-bit full subtractor, described at gate level.
// Used to build the ripple-borrow subtractor, which in turn provides
// the SUB operation and the magnitude comparison inside the divider.
//
//   diff = a XOR b XOR bin
//   bout = (~a & b) | (~a & bin) | (b & bin)
//======================================================================
`timescale 1ns / 1ps
`default_nettype none

module full_subtractor (
    input  wire a,      // minuend bit
    input  wire b,      // subtrahend bit
    input  wire bin,    // borrow in
    output wire diff,   // difference bit
    output wire bout    // borrow out
);

    assign diff = a ^ b ^ bin;
    assign bout = (~a & b) | (~a & bin) | (b & bin);

endmodule

`default_nettype wire
