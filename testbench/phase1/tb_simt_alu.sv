`timescale 1ns/1ps
// ============================================================================
// Testbench: Phase 1 - SIMT ALU (Random + Self-Checking)
// ----------------------------------------------------------------------------
// Purpose of Phase 1 TB:
//  1) Prove lane ALU ops are correct (ADD/SUB/MUL.LO/AND/OR/XOR/SLT)
//  2) Prove SIMT predication works (lane_mask controls commit vs pass-through)
//  3) Prove flags are correct on the *architectural* result (after predication)
//
// How to reuse this TB framework for future phases:
//  - Phase 2 (Predicate Mask Unit): keep the same structure but replace the
//    model with "mask update rules" and check mask outputs.
//  - Phase 3 (SIMT Stack): stimulus becomes branch events, monitor models stack.
//  - Phase 4 (Warp Scheduler): stimulus drives warp ready states, monitor models
//    round-robin choice, checker verifies selected warp.
// ============================================================================
module simt_alu_tb #(
    parameter int NUM_TESTS = 10000,
    parameter int DATA_WIDTH = 32,
    parameter int LANES = 8
);
    //PHASE A : Clock / Reset Generation:
    // Rule of thumb:
    //  - Keep clock generation isolated.
    //  - Keep reset sequencing deterministic and repeatable.

    logic clk = 1'b0;
    logic rst;
    
    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    //PHASE B : DUT Interface Signals
    // Tip: Name these exactly like DUT ports so you can use "DUT(.*)".

    logic in_valid;
    logic in_ready;
    logic out_valid;
    logic out_ready;
    logic [2:0] sel;
    logic [LANES-1:0] lane_mask;
    logic [LANES-1:0][DATA_WIDTH-1:0] a;
    logic [LANES-1:0][DATA_WIDTH-1:0] b;
    logic [LANES-1:0][DATA_WIDTH-1:0] result;
    logic [LANES-1:0] zero_l, pos_l, neg_l;

    //PHASE C : Expected / Scoreboard Storage
    // We compute expected values in MONITOR and store them here.
    // CHECKER compares DUT outputs against these expected values later.
    logic [LANES-1:0] [DATA_WIDTH-1:0] expected_result;
    logic [LANES-1:0] exp_zero, exp_pos, exp_neg;
    logic exp_valid_out;
    logic done;

    //PHASE D : Instantiate DUT
    // Tip: Use .* only if your TB signal names match DUT port names exactly.

    simt_alu #(
        .DATA_WIDTH(DATA_WIDTH),
        .LANES(LANES)
    ) DUT (.*);

    //PHASE E : Reference Model Functions (Golden Model)
    // Rule of thumb:
    //  - Keep the golden model SIMPLE and obviously correct.
    //  - Do not copy/paste DUT RTL into the model (that can hide bugs).

    // One-Lane ALU model
    function automatic logic [DATA_WIDTH-1:0] model_lane_out(
        input logic [2:0] sel,
        input logic [DATA_WIDTH-1:0] in0,
        input logic [DATA_WIDTH-1:0] in1
    );
        logic [2*DATA_WIDTH-1:0] prod;
        logic [DATA_WIDTH-1:0] y;
        begin
            y = '0;
            prod = '0;
            case (sel)
                3'b000: y = in0 + in1;
                3'b001: y = in0 - in1;
                3'b010: begin
                    prod = in0 * in1;
                    y = prod[DATA_WIDTH-1:0];
                end 
                3'b011: y = in0 & in1;
                3'b100: y = in0 | in1;
                3'b101: y = in0 ^ in1;
                3'b110: y = ($signed(in0) < $signed(in1)) ? 1'b1 : '0;
                default: y = '0;
            endcase

            return y;
        end
        
        
    endfunction

    // Flag models from final architectural value
    function automatic logic f_zero(input logic [DATA_WIDTH-1:0] x);
        return (x == '0);
    endfunction

    function automatic logic f_pos(input logic [DATA_WIDTH-1:0] x);
        return (x != '0) && (x[DATA_WIDTH-1] == 1'b0);
    endfunction

    function automatic logic f_neg(input logic [DATA_WIDTH-1:0] x);
        return (x[DATA_WIDTH-1] == 1'b1);
    endfunction

    //PHASE F: Stimulus Driver
    // Responsibilities:
    //  1) Apply reset sequence.
    //  2) Drive randomized transactions.
    //  3) Control in_valid/out_ready.
    //
    // For future phases:
    //  - Replace "sel/a/b/lane_mask randomization" with your new phase inputs.

    initial begin : provide_stimulus
        // Default Values
        rst <= 1'b0;
        in_valid <= 1'b0;
        out_ready <= 1'b0;
        sel <= '0;
        lane_mask <= '0;
        a <= '0;
        b <= '0;
        done <= 1'b0;

        //Reset
        repeat (5) @(posedge clk);
        rst <= 1'b1;
        repeat (2) @(posedge clk);

        //Deterministic seed (reproducibility)
        void'($urandom(32'hC0FFEE01));

        $display("PHASE 1: Starting %0d randomized transactions...", NUM_TESTS);

        for (int t = 0 ; t < NUM_TESTS ; t++ ) begin
            //Random sel : Only valid sel 0..6
            sel <= $urandom_range(0,6);

            //Random mask (SIMT predication)
            lane_mask <= $urandom();

            // Random Operands per lane
            for (int i = 0 ;i < LANES ; i++ ) begin
                a[i] <= $urandom();
                b[i] <= $urandom();
            end

            //Drive Transaction
            in_valid <= 1'b1;
            @(posedge clk);

            //Deassert valid (keeps waveform easier to read)
            in_valid <= 1'b0;
            @(posedge clk);
            
            if ((t % 1000) == 0) $display(" ---%0d/%0d driven", t , NUM_TESTS);
        end
        done <= 1'b1;
        $display("PHASE 1: Stimulus completed.");
        //disable generate_clock;
    end

    //PHASE G : Monitor / Expected Computation
    // Responsibilities:
    //  1) Observe inputs used for a transaction.
    //  2) Compute expected outputs using the reference model.
    //  3) Store results into exp_* variables for the checker.
    //
    // Important SIMT rule:
    //  - If lane_mask[i]==0, the architectural output is pass-through a[i]
    //    and flags must be computed from a[i] (not from raw ALU output).

    initial begin : monitor
        //Initialize expected to avoid X comparisions
        expected_result = '0;
        exp_pos = '0;
        exp_neg = '0;
        exp_zero = '0;
        exp_valid_out = 1'b0;

        forever begin
            @(posedge clk);
            //In Phase 1 v1: out_valid mirrors in_valid
            exp_valid_out = in_valid;

            if (in_valid) begin
                for (int i = 0  ;i < LANES ; i++ ) begin
                    logic [DATA_WIDTH-1:0] raw;
                    logic [DATA_WIDTH-1:0] final_value;

                    raw = model_lane_out(sel, a[i], b[i]);
                    final_value = lane_mask[i] ? raw : a[i]; // predication

                    expected_result[i] = final_value;
                    exp_pos[i] = f_pos(final_value);
                    exp_neg[i] = f_neg(final_value);
                    exp_zero[i] = f_zero(final_value);
                end
            end
        end
    end

    //PHASE H : Checker 
    // Responsibilities:
    //  1) Compare DUT outputs against exp_*.
    //  2) Use !== to catch X/Z mismatches.
    //  3) Stop early if too many errors.
    //
    // For future phases:
    //  - Keep this structure; only replace what you compare.

    initial begin : check_outputs
        int errors = 0;
        int checks = 0;

        forever begin
            @(posedge clk);

            //Only check cycles where we expect valid output
            if (in_valid) begin
                checks++;
                //For phase1 v1 wrapper: out_valid mirrors in_valid
                if (out_valid != 1'b1) begin
                    $error("out_valid mismatch: expected 1 got %b", out_valid);
                    errors++;
                end

                for (int i = 0 ; i < LANES ; i++ ) begin
                    if (result[i] !== expected_result[i]) begin
                        $error("Result mismatch lane %0d: expected = %h sel = %b mask=%b a=%h b=%h", i, expected_result[i], result[i], sel, lane_mask[i], a[i], b[i]);
                        errors++;
                    end
                    if (zero_l[i] !== exp_zero[i]) begin
                        $error("Zeros mismatch lane %0d: expected=%b got=%b val=%h", i, exp_zero[i], zero_l[i], expected_result[i]);
                        errors++;
                    end
                    if (pos_l[i] !== exp_pos[i]) begin
                        $error("Zeros mismatch lane %0d: expected=%b got=%b val=%h", i, exp_pos[i], pos_l[i], expected_result[i]);
                        errors++;
                    end
                    if (neg_l[i] !== exp_neg[i]) begin
                        $error("Zeros mismatch lane %0d: expected=%b got=%b val=%h", i, exp_neg[i], neg_l[i], expected_result[i]);
                        errors++;
                    end
                end

                if (errors > 50) begin
                    $display("Too may errors (%0d). Stopping early.", errors);
                    $finish;
                end
            end
            //End condition: Stimulus finished + we've checked all transactions
            if (done && (checks == NUM_TESTS)) begin
                $display("===============================");
                $display("PHASE 1 SUMMARY");
                $display("Checks Run : %0d", checks);
                $display("Errors : %0d", errors);
                if (errors == 0) begin
                    $display("Result : Pass");
                end
                else begin
                    $display("Result : Fail");
                end
                $display("===============================");
                $finish;
            end
        end
    end

endmodule





