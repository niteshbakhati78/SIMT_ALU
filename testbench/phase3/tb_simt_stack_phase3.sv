`timescale 1ns/1ps
// Testbench: Phase 3A - SIMT Stack (Directed + Self-Checking)
// Verifies:
//  1) LIFO ordering (last pushed is first popped)
//  2) empty/full/count behavior
//  3) pop outputs are registered (update on pop clock edge)
// NOTE:
//  - Expected computation is done inside the checker to avoid races.
//  - Stimulus drives on negedge, checking occurs on posedge.

module tb_simt_stack_phase3 #(
    parameter int LANES = 8,
    parameter int PC_W  = 16,
    parameter int DEPTH = 8
);

    // PHASE A: Clock/ Reset Generation
    logic clk = 1'b0;
    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    // PHASE B : DUT Interface Signals
    // Tip: Name these exactly like DUT ports so you can use "DUT(.*)".

    logic rst;
    logic push;
    logic [LANES-1:0] push_mask;
    logic [PC_W-1:0] push_pc;
    logic pop;
    logic [LANES-1:0] pop_mask;
    logic [PC_W-1:0] pop_pc;
    logic empty;
    logic full;
    logic [$clog2(DEPTH+1)-1:0] count;
    logic done;

    //PHASE C : Expected / Scoreboard Storage
    // We compute expected values in MONITOR and store them here.
    // CHECKER compares DUT outputs against these expected values later.

    //logic [LANES-1:0] sb_mask [DEPTH];
    //logic [PC_W-1:0]  sb_pc [DEPTH];

    //PHASE D : Instantiate DUT
    // Tip: Use .* only if your TB signal names match DUT port names exactly.
    simt_stack #(
        .LANES(LANES),
        .PC_W(PC_W),
        .DEPTH(DEPTH)
    ) DUT(.*);
    //PHASE E : Reference Model Functions (Golden Model)
    // Rule of thumb:
    //  - Keep the golden model SIMPLE and obviously correct.
    //  - Do not copy/paste DUT RTL into the model (that can hide bugs).

    logic [LANES-1:0] gold_mask_mem [DEPTH];
    logic [PC_W-1:0]  gold_pc_mem   [DEPTH];
    int unsigned      gold_sp; // 0..DEPTH

    task automatic gold_reset();
        gold_sp = 0;
        for (int i = 0; i < DEPTH; i++) begin
            gold_mask_mem[i] = '0;
            gold_pc_mem[i]   = '0;
        end
    endtask

    task automatic gold_push(input logic [LANES-1:0] m, input logic [PC_W-1:0] p);
        if (gold_sp < DEPTH) begin
            gold_mask_mem[gold_sp] = m;
            gold_pc_mem[gold_sp]   = p;
            gold_sp++;
        end
    endtask

    task automatic gold_pop(output logic [LANES-1:0] m, output logic [PC_W-1:0] p);
        if (gold_sp > 0) begin
            gold_sp--;
            m = gold_mask_mem[gold_sp];
            p = gold_pc_mem[gold_sp];
        end else begin
            m = '0;
            p = '0;
        end
    endtask


    //PHASE F: Stimulus Driver
    // Responsibilities:
    //  1) Apply reset sequence.
    //  2) Push DEPTH entries
    //  3) Pop  DEPTH entries

    initial begin : provide_stimulus
        // Defaults
        rst <= 1'b0;
        push <= 1'b0;
        pop <= 1'b0;
        push_mask <= '0;
        push_pc <= '0;
        done <= 1'b0;

        //deterministic seed (optional here, but keeps style consistent)
        //void'($urandom(32'hSTACK0001));
        void'($urandom(32'hFACECAFE));

        // Reset sequence
        repeat (2) @(negedge clk);
        rst <= 1'b1;
        @(negedge clk);
        rst <= 1'b0;

        // PUSH DEPTH entries
        for ( int i = 0 ; i < DEPTH ; i++ ) begin
            @(negedge clk);
            push <= 1'b1;
            pop <= 1'b0;

            //easy-to-debug pattern
            push_mask[i] <= (LANES'(1) << (i % LANES));
            push_pc[i] <= PC_W'(16'h100 + i);

            
            @(posedge clk);   // hold across sampling edge
            @(negedge clk);
            push <= 1'b0;
        end

        // Deassert push
        //@(negedge clk);
        //push <= 1'b0;

        // POP DEPTH entries
        for ( int j = 0 ; j < DEPTH ; j++ ) begin
            @(negedge clk);
            pop <= 1'b1;
            push <= 1'b0;

             @(posedge clk);   // hold across sampling edge
            @(negedge clk);
            pop <= 1'b0;
        end

        // Deassert pop
        //@(negedge clk);
        //pop <= 1'b0;

        // Let one more cycle pass so checker sees final state
        @(posedge clk);
        @(negedge clk);
        done <= 1'b1;
        $display("PHASE 3A: Stimulus completed.");

    end

    //PHASE G : Monitor / Expected Computation
    // Responsibilities:
    //  1) Observe inputs used for a transaction.
    //  2) Compute expected outputs using the reference model.
    //  3) Store results into exp_* variables for the checker.
    //PHASE H : Checker 
    // Responsibilities:
    //  1) Compare DUT outputs against exp_*.
    //  2) Use !== to catch X/Z mismatches.
    //  3) Stop early if too many errors.
    initial begin : check_outputs
        int errors = 0;
        int checks = 0;

        // Initialize golden model
        gold_reset();

        @(posedge clk);
        #1step;

        forever begin
            @(posedge clk);
            #1step; // sample AFTER DUT nonblocking updates

            // Keep golden model aligned with reset
            if (rst) begin
                gold_reset();
            end

            if (!done) begin
                // ---------------------------
                // PUSH check/update
                // ---------------------------
                if (push && !full) begin
                    gold_push(push_mask, push_pc);
                    checks++;

                    // Status checks
                    if (empty !== (gold_sp == 0)) begin
                        $error("EMPTY mismatch during push: exp=%b got=%b gold_sp=%0d",
                               (gold_sp==0), empty, gold_sp);
                        errors++;
                    end
                    if (count !== gold_sp[$bits(count)-1:0]) begin
                        $error("COUNT mismatch during push: exp=%0d got=%0d",
                               gold_sp, count);
                        errors++;
                    end
                    if (full !== (gold_sp == DEPTH)) begin
                        $error("FULL mismatch during push: exp=%b got=%b gold_sp=%0d",
                               (gold_sp==DEPTH), full, gold_sp);
                        errors++;
                    end
                end

                // ---------------------------
                // POP check/update
                // ---------------------------
                if (pop && !empty) begin
                    logic [LANES-1:0] exp_m;
                    logic [PC_W-1:0]  exp_p;

                    gold_pop(exp_m, exp_p);
                    checks++;

                    // Compare popped values
                    if (pop_mask !== exp_m) begin
                        $error("POP_MASK mismatch: exp=%b got=%b", exp_m, pop_mask);
                        errors++;
                    end
                    if (pop_pc !== exp_p) begin
                        $error("POP_PC mismatch: exp=%h got=%h", exp_p, pop_pc);
                        errors++;
                    end

                    // Status checks
                    if (empty !== (gold_sp == 0)) begin
                        $error("EMPTY mismatch during pop: exp=%b got=%b gold_sp=%0d",
                               (gold_sp==0), empty, gold_sp);
                        errors++;
                    end
                    if (count !== gold_sp[$bits(count)-1:0]) begin
                        $error("COUNT mismatch during pop: exp=%0d got=%0d",
                               gold_sp, count);
                        errors++;
                    end
                    if (full !== (gold_sp == DEPTH)) begin
                        $error("FULL mismatch during pop: exp=%b got=%b gold_sp=%0d",
                               (gold_sp==DEPTH), full, gold_sp);
                        errors++;
                    end
                end
            end

            // End + summary
            if (done) begin
                // At end, we expect empty and count=0
                if (!empty) begin
                    $error("End check: expected empty=1 got empty=%b count=%0d", empty, count);
                    errors++;
                end
                if (count !== '0) begin
                    $error("End check: expected count=0 got count=%0d", count);
                    errors++;
                end

                $display("====================================");
                $display("PHASE 3A SUMMARY (SIMT STACK)");
                $display("  Checks run : %0d", checks);
                $display("  Errors     : %0d", errors);
                if (errors == 0) $display("  RESULT     : PASS");
                else             $display("  RESULT     : FAIL");
                $display("====================================");
                $finish;
            end
        end
    end
    //
    // For future phases:
    //  - Keep this structure; only replace what you compare.

    
endmodule