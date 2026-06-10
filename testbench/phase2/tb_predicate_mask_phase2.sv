`timescale 1ns/1ps

// Testbench: Phase 2 - Predicate Mask Unit (Random + Self-Checking)
// What we verify:
//  - enable=0 -> output mask equals input mask
//  - enable=1 -> output mask = mask_in & (invert ? ~cond : cond)
//  - any_active matches (mask_out != 0)
//NOTE:
//Expected computation is done inside the checker to avoid monitor/checker race.
//Stimulus drives on negedge, checking occurs on posedge.

module tb_predicate_mask_phase2 #(
    parameter int NUM_TESTS = 10000,
    parameter int LANES = 8
);

    // PHASE A: Clock/ Reset Generation

    logic clk = 1'b0;
    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    //PHASE B : DUT Interface Signals
    // Tip: Name these exactly like DUT ports so you can use "DUT(.*)".

    logic [LANES-1:0] lane_mask_in;
    logic [LANES-1:0] cond;
    logic             invert;
    logic             enable;
    logic [LANES-1:0] lane_mask_out;
    logic             any_active;
    logic             done;



    //PHASE C : Expected / Scoreboard Storage
    // We compute expected values in MONITOR and store them here.
    // CHECKER compares DUT outputs against these expected values later.

    logic [LANES-1:0] exp_mask_out;
    logic             exp_any_active;


    //PHASE D : Instantiate DUT
    // Tip: Use .* only if your TB signal names match DUT port names exactly.

    predicate_mask_unit #(
        .LANES(LANES)
    ) DUT (
        .lane_mask_in(lane_mask_in),
        .cond(cond),
        .invert(invert),
        .enable(enable),
        .lane_mask_out(lane_mask_out),
        .any_active(any_active)
    );

    //PHASE E : Reference Model Functions (Golden Model)
    // Rule of thumb:
    //  - Keep the golden model SIMPLE and obviously correct.
    //  - Do not copy/paste DUT RTL into the model (that can hide bugs).

    function automatic logic [LANES-1:0] model_mask(
        input logic [LANES-1:0] m_in,
        input logic [LANES-1:0] c,
        input logic             inv,
        input logic             en
    );
        logic [LANES-1:0] csel;
        begin
            csel = inv ? ~c : c;
            if (en) begin
                return (m_in & csel);
            end
            else begin
                return (m_in);
            end
        end
        
    endfunction

    //PHASE F: Stimulus Driver
    // Responsibilities:
    //  1) Apply reset sequence.
    //  2) Drive randomized transactions.
    //  3) Control in_valid/out_ready.
    //
    initial begin : provide_stimulus
        lane_mask_in <= '0;
        cond         <= '0;
        enable       <= 1'b0;
        invert       <= 1'b0;
        done         <= 1'b0;

        //@(posedge clk);

        void'($urandom(32'hBEEF1234));
        $display("PHASE 2: Starting %0d randomized tests...", NUM_TESTS);

        for (int t = 0; t < NUM_TESTS ; t++ ) begin
            //Drive on negedge so DUT settles before we sample on posedge.
            @(negedge clk);
            lane_mask_in <= $urandom();
            cond         <= $urandom();
            invert       <= $urandom_range(0,1);
            enable       <= $urandom_range(0,1);

            if ((t % 1000) == 0) $display("  ...%0d/%0d driven", t, NUM_TESTS);
        end
        //Let one more cycle pass so checker sees final vector.
        @(negedge clk);
        done <= 1'b1;
        $display("PHASE 2: Stimulus completed.");
    end

    //PHASE G : Monitor / Expected Computation
    // Responsibilities:
    //  1) Observe inputs used for a transaction.
    //  2) Compute expected outputs using the reference model.
    //  3) Store results into exp_* variables for the checker.

    /*initial begin : monitor
        exp_mask_out = '0;
        exp_any_active = 1'b0;

        forever begin
            @(posedge clk);
            exp_mask_out = model_mask(lane_mask_in, cond, invert, enable);
            exp_any_active = (exp_mask_out != '0);
        end
    end*/


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
        @(posedge clk);

        forever begin
            @(posedge clk);
            // Only count checks while we are still running tests
            if (!done) begin
                logic [LANES-1:0] exp_mask_out;
                logic             exp_any_active;

                exp_mask_out   = model_mask(lane_mask_in, cond, invert, enable);
                exp_any_active = (exp_mask_out != '0);

                checks++;
            
                //Compare the vector mask output
                if (lane_mask_out !== exp_mask_out) begin
                    $error("MASK mismatch: exp=%b got=%b | in=%b cond=%b inv=%0d en=%0d", exp_mask_out, lane_mask_out, lane_mask_in, cond, invert, enable);
                    errors++;
                end
                //Compare 1-bit any_active
                if (any_active !== exp_any_active) begin
                    $error("ANY_ACTIVE mismatch: exp=%b got=%b | mask_out=%b", exp_any_active, any_active, lane_mask_out);
                    errors++;
                end
                //if (errors > 50) begin
                //  $display("Too many errors (%0d). Stopping early.", errors);
                // $finish;
                //end
            end    

            if (done) begin
                $display("====================================");
                $display("PHASE 2 SUMMARY");
                $display("  Checks run : %0d", checks);
                $display("  Errors     : %0d", errors);
                if (errors == 0) $display("  RESULT     : PASS ");
                else             $display("  RESULT     : FAIL ");
                $display("====================================");
                $finish;
            end
        end
    end




endmodule