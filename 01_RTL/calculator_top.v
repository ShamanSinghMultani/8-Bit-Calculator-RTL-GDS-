//======================================================================
// calculator_top.v
//----------------------------------------------------------------------
// 8-bit arithmetic calculator: ADD / SUB / MUL / DIV.
//
// Structure
// ---------
//   calculator_top
//     |- ripple_carry_adder        (ADD)  <- full_adder x WIDTH
//     |- ripple_borrow_subtractor  (SUB)  <- full_subtractor x WIDTH
//     |- array_multiplier          (MUL)  <- ripple_carry_adder rows
//     `- restoring_divider         (DIV)  <- ripple_borrow_subtractor
//
// ADD/SUB/MUL are combinational and retire in a single cycle. DIV is
// sequential (WIDTH cycles), so the top level is a small FSM that holds
// the request until the divider reports done.
//
// Handshake
// ---------
//   start : pulse high for one cycle with opcode/operands valid
//   busy  : high while an operation is in flight (ignore start)
//   done  : one-cycle pulse; result and flags are valid on this edge
//           and are held until the next accepted start.
//
// Result encoding
// ---------------
//   ADD : {7'b0, carry, sum[7:0]}       full 9-bit sum, never truncated
//   SUB : {8'b0, diff[7:0]}             borrow flag set when a < b
//   MUL : product[15:0]                 exact, never truncated
//   DIV : {remainder[7:0], quotient[7:0]}
//======================================================================
`timescale 1ns / 1ps
`default_nettype none

module calculator_top #(
    parameter integer WIDTH = 8
)(
    input  wire                 clk,
    input  wire                 rst_n,       // active-low synchronous reset
    input  wire                 start,
    input  wire [2:0]           opcode,
    input  wire [WIDTH-1:0]     operand_a,
    input  wire [WIDTH-1:0]     operand_b,

    output reg  [2*WIDTH-1:0]   result,
    output reg                  done,
    output wire                 busy,
    // ---- status flags -------------------------------------------------
    output reg                  flag_zero,        // result == 0
    output reg                  flag_carry,       // ADD produced a carry-out
    output reg                  flag_borrow,      // SUB underflowed (a < b)
    output reg                  flag_div_zero,    // DIV by zero
    output reg                  flag_invalid_op   // unrecognised opcode
);

    // ---- Opcode map ---------------------------------------------------
    localparam [2:0] OP_ADD = 3'b000;
    localparam [2:0] OP_SUB = 3'b001;
    localparam [2:0] OP_MUL = 3'b010;
    localparam [2:0] OP_DIV = 3'b011;

    // ---- FSM states ---------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0,
                     S_DIV  = 2'd1;

    reg [1:0] state;

    // ================= Combinational arithmetic units ===================
    wire [WIDTH-1:0] add_sum;
    wire             add_cout;
    ripple_carry_adder #(.WIDTH(WIDTH)) u_add (
        .a(operand_a), .b(operand_b), .cin(1'b0),
        .sum(add_sum), .cout(add_cout)
    );

    wire [WIDTH-1:0] sub_diff;
    wire             sub_bout;
    ripple_borrow_subtractor #(.WIDTH(WIDTH)) u_sub (
        .a(operand_a), .b(operand_b), .bin(1'b0),
        .diff(sub_diff), .bout(sub_bout)
    );

    wire [2*WIDTH-1:0] mul_product;
    array_multiplier #(.WIDTH(WIDTH)) u_mul (
        .a(operand_a), .b(operand_b), .product(mul_product)
    );

    // ================= Sequential divider ===============================
    // The divider samples its operands the cycle *after* div_start is
    // asserted, so latch them here instead of requiring the caller to
    // hold operand_a/operand_b stable for a second cycle.
    reg [WIDTH-1:0]  div_a_r, div_b_r;

    reg              div_start;
    wire [WIDTH-1:0] div_quotient;
    wire [WIDTH-1:0] div_remainder;
    wire             div_by_zero;
    wire             div_busy;
    wire             div_done;

    restoring_divider #(.WIDTH(WIDTH)) u_div (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (div_start),
        .dividend    (div_a_r),
        .divisor     (div_b_r),
        .quotient    (div_quotient),
        .remainder   (div_remainder),
        .div_by_zero (div_by_zero),
        .busy        (div_busy),
        .done        (div_done)
    );

    assign busy = (state != S_IDLE);

    // ================= Control FSM ======================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            div_a_r         <= {WIDTH{1'b0}};
            div_b_r         <= {WIDTH{1'b0}};
            result          <= {(2*WIDTH){1'b0}};
            done            <= 1'b0;
            div_start       <= 1'b0;
            flag_zero       <= 1'b0;
            flag_carry      <= 1'b0;
            flag_borrow     <= 1'b0;
            flag_div_zero   <= 1'b0;
            flag_invalid_op <= 1'b0;
        end else begin
            done      <= 1'b0;          // done is a 1-cycle pulse
            div_start <= 1'b0;

            case (state)
            //-------------------------------------------------------------
            S_IDLE: begin
                if (start) begin
                    // Clear flags for the new operation.
                    flag_carry      <= 1'b0;
                    flag_borrow     <= 1'b0;
                    flag_div_zero   <= 1'b0;
                    flag_invalid_op <= 1'b0;

                    case (opcode)
                    OP_ADD: begin
                        result     <= {{(WIDTH-1){1'b0}}, add_cout, add_sum};
                        flag_carry <= add_cout;
                        flag_zero  <= ~(|{add_cout, add_sum});
                        done       <= 1'b1;
                    end

                    OP_SUB: begin
                        result      <= {{WIDTH{1'b0}}, sub_diff};
                        flag_borrow <= sub_bout;
                        flag_zero   <= ~(|sub_diff);
                        done        <= 1'b1;
                    end

                    OP_MUL: begin
                        result    <= mul_product;
                        flag_zero <= ~(|mul_product);
                        done      <= 1'b1;
                    end

                    OP_DIV: begin
                        // Latch operands and hand off to the sequential divider.
                        div_a_r   <= operand_a;
                        div_b_r   <= operand_b;
                        div_start <= 1'b1;
                        state     <= S_DIV;
                    end

                    default: begin
                        // Unrecognised opcode: retire immediately with a flag.
                        result          <= {(2*WIDTH){1'b0}};
                        flag_invalid_op <= 1'b1;
                        flag_zero       <= 1'b1;
                        done            <= 1'b1;
                    end
                    endcase
                end
            end
            //-------------------------------------------------------------
            S_DIV: begin
                if (div_done) begin
                    result        <= {div_remainder, div_quotient};
                    flag_div_zero <= div_by_zero;
                    flag_zero     <= ~(|{div_remainder, div_quotient});
                    done          <= 1'b1;
                    state         <= S_IDLE;
                end
            end
            //-------------------------------------------------------------
            default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
