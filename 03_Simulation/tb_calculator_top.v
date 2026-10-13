//======================================================================
// tb_calculator_top.v
//----------------------------------------------------------------------
// Self-checking Verilog testbench for calculator_top, written for the
// Vivado Simulator (XSim).
//
// The testbench runs in two phases:
//
//   PHASE 1 -- DEMONSTRATION
//     A small number of operations, widely spaced in time, so that each
//     one is easy to point at in the waveform window during the viva.
//
//   PHASE 2 -- SELF-CHECKING REGRESSION
//     Directed corner cases followed by randomised stimulus. Every
//     result is compared against an independent reference computed with
//     Verilog's built-in arithmetic operators. Nothing is judged by
//     eye: the testbench counts passes and failures and prints a
//     verdict at the end.
//
// Why the reference model is trustworthy: the design under test never
// uses +, -, * or /. It is built structurally from full-adder and
// full-subtractor cells. The testbench uses the built-in operators.
// The two are therefore genuinely independent descriptions of the same
// arithmetic, which is what makes the comparison meaningful.
//======================================================================
`timescale 1ns / 1ps

module tb_calculator_top;

    //------------------------------------------------------------------
    // Parameters
    //------------------------------------------------------------------
    localparam integer WIDTH      = 8;
    localparam integer CLK_PERIOD = 10;          // 100 MHz

    // Opcode encoding (must match calculator_top.v)
    localparam [2:0] OP_ADD = 3'b000;
    localparam [2:0] OP_SUB = 3'b001;
    localparam [2:0] OP_MUL = 3'b010;
    localparam [2:0] OP_DIV = 3'b011;

    //------------------------------------------------------------------
    // DUT connections
    //------------------------------------------------------------------
    reg                    clk;
    reg                    rst_n;
    reg                    start;
    reg  [2:0]             opcode;
    reg  [WIDTH-1:0]       operand_a;
    reg  [WIDTH-1:0]       operand_b;

    wire [2*WIDTH-1:0]     result;
    wire                   done;
    wire                   busy;
    wire                   flag_zero;
    wire                   flag_carry;
    wire                   flag_borrow;
    wire                   flag_div_zero;
    wire                   flag_invalid_op;

    //------------------------------------------------------------------
    // Bookkeeping
    //------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer i;

    // Split-out views of the DIV result, purely to make the waveform
    // readable -- quotient and remainder as separate named signals.
    wire [WIDTH-1:0] div_quotient  = result[WIDTH-1:0];
    wire [WIDTH-1:0] div_remainder = result[2*WIDTH-1:WIDTH];

    //------------------------------------------------------------------
    // Device under test
    //------------------------------------------------------------------
    calculator_top #(
        .WIDTH (WIDTH)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .opcode          (opcode),
        .operand_a       (operand_a),
        .operand_b       (operand_b),
        .result          (result),
        .done            (done),
        .busy            (busy),
        .flag_zero       (flag_zero),
        .flag_carry      (flag_carry),
        .flag_borrow     (flag_borrow),
        .flag_div_zero   (flag_div_zero),
        .flag_invalid_op (flag_invalid_op)
    );

    //------------------------------------------------------------------
    // Clock generation : 100 MHz
    //------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //------------------------------------------------------------------
    // Helper : printable operation name
    //------------------------------------------------------------------
    function [31:0] op_name;
        input [2:0] op;
        begin
            case (op)
                OP_ADD : op_name = "ADD";
                OP_SUB : op_name = "SUB";
                OP_MUL : op_name = "MUL";
                OP_DIV : op_name = "DIV";
                default: op_name = "BAD";
            endcase
        end
    endfunction

    //------------------------------------------------------------------
    // Reset
    //------------------------------------------------------------------
    task apply_reset;
        begin
            rst_n     = 1'b0;
            start     = 1'b0;
            opcode    = OP_ADD;
            operand_a = 8'd0;
            operand_b = 8'd0;
            repeat (3) @(negedge clk);
            rst_n     = 1'b1;
            @(negedge clk);
        end
    endtask

    //------------------------------------------------------------------
    // Drive one operation, wait for done, and check the result.
    //
    // check = 1 : compare against the reference and count pass/fail
    // check = 0 : just run it (used for the demonstration phase)
    //------------------------------------------------------------------
    task run_op;
        input [2:0]       op;
        input [WIDTH-1:0] a;
        input [WIDTH-1:0] b;
        input             check;

        reg [2*WIDTH-1:0] exp_result;
        reg               exp_zero;
        reg               exp_carry;
        reg               exp_borrow;
        reg               exp_div_zero;
        reg               ok;
        integer           timeout;
        begin
            // ---------------- drive the request --------------------
            @(negedge clk);
            opcode    = op;
            operand_a = a;
            operand_b = b;
            start     = 1'b1;
            @(negedge clk);
            start     = 1'b0;

            // ---------------- wait for completion ------------------
            timeout = 0;
            while ((done !== 1'b1) && (timeout < 64)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            if (done !== 1'b1) begin
                $display("[%0t] TIMEOUT  %0s a=%0d b=%0d : done never asserted",
                         $time, op_name(op), a, b);
                fail_count = fail_count + 1;
                disable run_op;
            end

            // ---------------- reference model ----------------------
            // Computed with Verilog's built-in operators, which the
            // design under test deliberately never uses.
            exp_carry    = 1'b0;
            exp_borrow   = 1'b0;
            exp_div_zero = 1'b0;

            case (op)
                OP_ADD : begin
                    exp_result = a + b;                 // full 9-bit sum
                    exp_carry  = ((a + b) > 16'd255);
                end
                OP_SUB : begin
                    exp_result = (a - b) & 16'h00FF;    // wraps on underflow
                    exp_borrow = (a < b);
                end
                OP_MUL : begin
                    exp_result = a * b;                 // exact 16-bit product
                end
                OP_DIV : begin
                    if (b == 8'd0) begin
                        exp_result   = {a, 8'hFF};      // saturating convention
                        exp_div_zero = 1'b1;
                    end else begin
                        exp_result   = {(a % b), (a / b)};
                    end
                end
                default : exp_result = 16'h0000;
            endcase

            exp_zero = (exp_result == 16'h0000);

            // ---------------- compare ------------------------------
            ok = (result        === exp_result  ) &&
                 (flag_zero     === exp_zero    ) &&
                 (flag_carry    === exp_carry   ) &&
                 (flag_borrow   === exp_borrow  ) &&
                 (flag_div_zero === exp_div_zero);

            if (check) begin
                if (ok) begin
                    pass_count = pass_count + 1;
                end else begin
                    fail_count = fail_count + 1;
                    $display("[%0t] *** FAIL *** %0s a=%0d b=%0d : got 0x%04h exp 0x%04h  (Z=%b/%b C=%b/%b B=%b/%b DZ=%b/%b)",
                             $time, op_name(op), a, b, result, exp_result,
                             flag_zero, exp_zero, flag_carry, exp_carry,
                             flag_borrow, exp_borrow, flag_div_zero, exp_div_zero);
                end
            end
        end
    endtask

    //------------------------------------------------------------------
    // Print one operation in a readable form (demonstration phase)
    //------------------------------------------------------------------
    task show_op;
        input [2:0]       op;
        input [WIDTH-1:0] a;
        input [WIDTH-1:0] b;
        begin
            run_op(op, a, b, 1'b1);
            case (op)
                OP_ADD : $display("  t=%0t ns |  %3d  +  %3d  =  %5d      | carry=%b zero=%b",
                                  $time, a, b, result, flag_carry, flag_zero);
                OP_SUB : $display("  t=%0t ns |  %3d  -  %3d  =  %5d      | borrow=%b zero=%b",
                                  $time, a, b, result[7:0], flag_borrow, flag_zero);
                OP_MUL : $display("  t=%0t ns |  %3d  x  %3d  =  %5d      | zero=%b",
                                  $time, a, b, result, flag_zero);
                OP_DIV : begin
                    if (flag_div_zero)
                        $display("  t=%0t ns |  %3d  /  %3d  =  DIVIDE BY ZERO  | div_zero=%b",
                                 $time, a, b, flag_div_zero);
                    else
                        $display("  t=%0t ns |  %3d  /  %3d  =  %3d rem %3d    | div_zero=%b",
                                 $time, a, b, div_quotient, div_remainder, flag_div_zero);
                end
                default : $display("  invalid opcode %b               | invalid=%b",
                                   op, flag_invalid_op);
            endcase
            #40;    // gap between operations, keeps the waveform readable
        end
    endtask

    //==================================================================
    // Main stimulus
    //==================================================================
    initial begin
        // Print $time in nanoseconds rather than raw picosecond ticks,
        // so the console timestamps match the waveform time axis.
        $timeformat(-9, 0, "", 8);

        pass_count = 0;
        fail_count = 0;

        $display("");
        $display("======================================================");
        $display("  8-BIT ARITHMETIC CALCULATOR - TESTBENCH");
        $display("  Design Implementation of an 8-Bit Arithmetic");
        $display("  Calculator Using Verilog from RTL-to-GDSII");
        $display("======================================================");

        apply_reset;

        //--------------------------------------------------------------
        // PHASE 1 : DEMONSTRATION
        //--------------------------------------------------------------
        $display("");
        $display("------------------------------------------------------");
        $display(" PHASE 1 : DEMONSTRATION");
        $display("------------------------------------------------------");

        $display(" ADDITION");
        show_op(OP_ADD,  25,  17);      // simple
        show_op(OP_ADD, 200,  100);     // carry out of 8 bits

        $display(" SUBTRACTION");
        show_op(OP_SUB,  90,  35);      // simple
        show_op(OP_SUB,  20,  50);      // borrow / underflow

        $display(" MULTIPLICATION");
        show_op(OP_MUL,  12,  12);      // simple
        show_op(OP_MUL, 255, 255);      // widest product

        $display(" DIVISION");
        show_op(OP_DIV, 144,  12);      // exact
        show_op(OP_DIV, 100,   7);      // with remainder
        show_op(OP_DIV,  50,   0);      // divide by zero

        //--------------------------------------------------------------
        // PHASE 2 : SELF-CHECKING REGRESSION
        //--------------------------------------------------------------
        $display("");
        $display("------------------------------------------------------");
        $display(" PHASE 2 : SELF-CHECKING REGRESSION");
        $display("------------------------------------------------------");

        // ---- directed corner cases --------------------------------
        run_op(OP_ADD,   0,   0, 1'b1);
        run_op(OP_ADD, 255, 255, 1'b1);
        run_op(OP_ADD,   1, 255, 1'b1);
        run_op(OP_ADD, 128, 128, 1'b1);
        run_op(OP_SUB,   0,   0, 1'b1);
        run_op(OP_SUB, 255, 255, 1'b1);
        run_op(OP_SUB,   0,   1, 1'b1);
        run_op(OP_SUB, 255,   0, 1'b1);
        run_op(OP_MUL,   0,   0, 1'b1);
        run_op(OP_MUL,   1, 255, 1'b1);
        run_op(OP_MUL, 255, 255, 1'b1);
        run_op(OP_MUL,  16,  16, 1'b1);
        run_op(OP_DIV,   0,   1, 1'b1);
        run_op(OP_DIV, 255,   1, 1'b1);
        run_op(OP_DIV, 255, 255, 1'b1);
        run_op(OP_DIV,   1, 255, 1'b1);
        run_op(OP_DIV, 254,   2, 1'b1);
        run_op(OP_DIV,   0,   0, 1'b1);
        run_op(OP_DIV, 255,   0, 1'b1);
        $display(" Directed corner cases complete : %0d passed, %0d failed",
                 pass_count, fail_count);

        // ---- invalid opcodes --------------------------------------
        run_op(3'b100, 8'hAB, 8'hCD, 1'b1);
        run_op(3'b111, 8'h12, 8'h34, 1'b1);

        // ---- randomised stimulus ----------------------------------
        for (i = 0; i < 200; i = i + 1) begin
            run_op({$random} % 4, {$random} % 256, {$random} % 256, 1'b1);
        end
        $display(" Randomised stimulus complete.");

        //--------------------------------------------------------------
        // Verdict
        //--------------------------------------------------------------
        $display("");
        $display("======================================================");
        $display("  RESULTS : %0d passed, %0d failed, %0d total",
                 pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  OVERALL : ***** ALL TESTS PASSED *****");
        else
            $display("  OVERALL : ***** %0d FAILURES - SEE LOG *****", fail_count);
        $display("======================================================");
        $display("");

        #100;
        $finish;
    end

endmodule
