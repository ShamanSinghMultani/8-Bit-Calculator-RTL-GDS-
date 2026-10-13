//======================================================================
// restoring_divider.v
//----------------------------------------------------------------------
// WIDTH-bit unsigned restoring division, sequential (WIDTH cycles).
//
// Unlike ADD/SUB/MUL, division has no cheap combinational form, so this
// block is multi-cycle and handshakes with the top level using
// start / busy / done. This is the only stateful arithmetic unit in the
// design and it is what forces the calculator to have an FSM at all.
//
// Algorithm (restoring division on a 2*WIDTH-bit accumulator):
//   acc = { 0 , dividend }                       // rem | quo
//   repeat WIDTH times:
//       acc = acc << 1                           // bring down next bit
//       if (acc.rem >= divisor)                  // trial subtraction
//           acc.rem = acc.rem - divisor          //   keep it
//           acc.quo[0] = 1
//       else
//           (leave acc.rem alone)                //   "restore"
//   quotient  = acc.quo
//   remainder = acc.rem
//
// The trial subtraction and the ">=" comparison are done in one shot by
// the ripple_borrow_subtractor: its borrow-out is 1 exactly when
// rem < divisor, so no separate comparator is needed.
//
// Divide-by-zero: flagged, and the conventional saturating result is
// returned (quotient = all ones, remainder = dividend) so the block
// never hangs.
//======================================================================
`timescale 1ns / 1ps
`default_nettype none

module restoring_divider #(
    parameter integer WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,       // active-low synchronous reset
    input  wire             start,       // pulse to begin a division
    input  wire [WIDTH-1:0] dividend,
    input  wire [WIDTH-1:0] divisor,

    output reg  [WIDTH-1:0] quotient,
    output reg  [WIDTH-1:0] remainder,
    output reg              div_by_zero,
    output reg              busy,
    output reg              done         // 1-cycle pulse when finished
);

    localparam integer CNTW = $clog2(WIDTH) + 1;

    // acc[2W-1:W] = working remainder, acc[W-1:0] = developing quotient
    reg  [2*WIDTH-1:0] acc;
    reg  [WIDTH-1:0]   divisor_r;
    reg  [CNTW-1:0]    count;

    // ---- Combinational trial subtraction on the shifted accumulator --
    wire [2*WIDTH-1:0] acc_shifted = acc << 1;
    wire [WIDTH-1:0]   rem_shifted = acc_shifted[2*WIDTH-1:WIDTH];

    wire [WIDTH-1:0]   trial_diff;
    wire               trial_borrow;    // 1 => rem_shifted < divisor_r

    ripple_borrow_subtractor #(.WIDTH(WIDTH)) u_trial_sub (
        .a    (rem_shifted),
        .b    (divisor_r),
        .bin  (1'b0),
        .diff (trial_diff),
        .bout (trial_borrow)
    );

    wire fits = ~trial_borrow;          // divisor fits into the remainder

    // ---- Control / datapath ------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            acc         <= {(2*WIDTH){1'b0}};
            divisor_r   <= {WIDTH{1'b0}};
            count       <= {CNTW{1'b0}};
            quotient    <= {WIDTH{1'b0}};
            remainder   <= {WIDTH{1'b0}};
            div_by_zero <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;               // default: done is a 1-cycle pulse

            if (!busy) begin
                if (start) begin
                    if (divisor == {WIDTH{1'b0}}) begin
                        // Division by zero: answer immediately, do not stall.
                        quotient    <= {WIDTH{1'b1}};
                        remainder   <= dividend;
                        div_by_zero <= 1'b1;
                        done        <= 1'b1;
                        busy        <= 1'b0;
                    end else begin
                        acc         <= {{WIDTH{1'b0}}, dividend};
                        divisor_r   <= divisor;
                        count       <= WIDTH[CNTW-1:0];
                        div_by_zero <= 1'b0;
                        busy        <= 1'b1;
                    end
                end
            end else begin
                // One restoring-division iteration per clock.
                if (fits)
                    acc <= {trial_diff, acc_shifted[WIDTH-1:0] | {{(WIDTH-1){1'b0}}, 1'b1}};
                else
                    acc <= acc_shifted;

                count <= count - 1'b1;

                if (count == {{(CNTW-1){1'b0}}, 1'b1}) begin
                    // Last iteration: latch the results being computed now.
                    if (fits) begin
                        remainder <= trial_diff;
                        quotient  <= acc_shifted[WIDTH-1:0] | {{(WIDTH-1){1'b0}}, 1'b1};
                    end else begin
                        remainder <= rem_shifted;
                        quotient  <= acc_shifted[WIDTH-1:0];
                    end
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
