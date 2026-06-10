`timescale 1ns/1ps
// ============================================================================
// Testbench: Phase 3B - SIMT Branch Control (Directed + Self-Checking)
// What we verify:
//  - Divergence split: then_mask = mask_in & cond, else_mask = mask_in & ~cond
//  - THEN-first policy on divergence:
//      * mask_out becomes then_mask
//      * else_mask is pushed onto stack
//  - On path_done:
//      * controller pops and resumes else_mask (one cycle later due to POP_WAIT)
//
// NOTE:
//  - Expected computation is done inside the checker to avoid races.
//  - Stimulus drives on negedge, checking occurs on posedge.
// ============================================================================

module tb_branch_control_phase3 #(
    parameter int LANES = 8,
    parameter int PC_W  = 16,
    parameter int STACK_DEPTH = 8
);

    // PHASE A: Clock Generation
    logic clk = 1'b0;
    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    // PHASE B: DUT Interface Signals
    logic rst;

    logic [LANES-1:0] mask_in;
    logic [PC_W-1:0]  pc_in;

    logic             branch_valid;
    logic [LANES-1:0] cond;
    logic [PC_W-1:0]  reconverge_pc;

    logic             path_done;

    logic [LANES-1:0] mask_out;
    logic [PC_W-1:0]  pc_out;

    logic stack_empty;
    logic stack_full;

    logic done;

    // PHASE D: Instantiate DUT
    simt_branch_control #(
        .LANES(LANES),
        .PC_W(PC_W),
        .STACK_DEPTH(STACK_DEPTH)
    ) DUT (.*);

    // PHASE F: Stimulus Driver
    initial begin : provide_stimulus
        // defaults
        rst           <= 1'b0;
        mask_in       <= '0;
        pc_in         <= '0;
        branch_valid  <= 1'b0;
        cond          <= '0;
        reconverge_pc <= '0;
        path_done     <= 1'b0;
        done          <= 1'b0;

        //void'($urandom(32'hBRCH0001));
        void'($urandom(32'hFACECAFE));

        // Reset
        repeat (2) @(negedge clk);
        rst <= 1'b1;
        @(negedge clk);
        rst <= 1'b0;

        // ---------------------------
        // Drive a divergence event
        // ---------------------------
        // Example:
        // mask_in = 11111111
        // cond    = 11001010
        // then    = 11001010
        // else    = 00110101
        @(negedge clk);
        mask_in       <= 8'b11111111;
        cond          <= 8'b11001010;
        pc_in         <= PC_W'(16'h0200);
        reconverge_pc <= PC_W'(16'h0300);
        branch_valid  <= 1'b1;

        @(negedge clk);
        branch_valid  <= 1'b0;

        // ---------------------------
        // Signal end of THEN path
        // ---------------------------
        // path_done causes a pop request; controller resumes popped context
        // one cycle later due to POP_WAIT.
        @(negedge clk);
        path_done <= 1'b1;

        @(negedge clk);
        path_done <= 1'b0;

        // let a couple cycles settle
        repeat (2) @(negedge clk);

        done <= 1'b1;
        $display("PHASE 3B: Stimulus completed.");
    end

    // PHASE H: Checker
    initial begin : check_outputs
        int errors = 0;
        int checks = 0;

        // precompute expected masks for our directed case
        logic [LANES-1:0] exp_then;
        logic [LANES-1:0] exp_else;

        // Track what stage we are in
        // 0: waiting for branch to be observed
        // 1: after branch, expecting then_mask
        // 2: after path_done, waiting 1 cycle (POP_WAIT)
        // 3: expecting else_mask
        int stage = 0;

        @(posedge clk);

        forever begin
            @(posedge clk);

            // expected based on current driven inputs (directed constants here)
            exp_then = mask_in &  cond;
            exp_else = mask_in & ~cond;

            if (!done) begin
                // Stage transitions based on observed events
                // We key off branch_valid / path_done on the *posedge* sampling points.

                if (stage == 0) begin
                    // Wait until we see the branch_valid asserted on a sampled edge
                    if (branch_valid) begin
                        stage = 1;
                    end
                end

                else if (stage == 1) begin
                    // After divergence, controller should select THEN-first
                    checks++;
                    if (mask_out !== exp_then) begin
                        $error("After divergence: expected mask_out=THEN %b got %b", exp_then, mask_out);
                        errors++;
                    end
                    // stack should have pushed else => stack_empty should be 0
                    checks++;
                    if (stack_empty !== 1'b0) begin
                        $error("After divergence: expected stack_empty=0 got %b", stack_empty);
                        errors++;
                    end
                    // Move forward when we see path_done
                    if (path_done) begin
                        stage = 2;
                    end
                end

                else if (stage == 2) begin
                    // POP_WAIT cycle: controller is waiting for stack pop outputs
                    // We do not check mask_out yet; it will update next cycle.
                    stage = 3;
                end

                else if (stage == 3) begin
                    // Now we expect ELSE mask after pop
                    checks++;
                    if (mask_out !== exp_else) begin
                        $error("After path_done pop: expected mask_out=ELSE %b got %b", exp_else, mask_out);
                        errors++;
                    end
                    // We’re done with the directed checks
                    stage = 4;
                end
            end

            if (done) begin
                $display("====================================");
                $display("PHASE 3B SUMMARY (BRANCH CONTROL)");
                $display("  Checks run : %0d", checks);
                $display("  Errors     : %0d", errors);
                if (errors == 0) $display("  RESULT     : PASS");
                else             $display("  RESULT     : FAIL");
                $display("====================================");
                $finish;
            end
        end
    end

endmodule
