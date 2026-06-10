`timescale 1ns/1ps
// ============================================================================
// Testbench: Phase 4 — Mini-SM Integration (Directed + Self-Checking)
// + Extension 1: $fwrite stats dump for Python perf sweep
// ============================================================================
// Tests:
//   Test 1 — Single-warp RAW stall
//     Warp 0 issues I1 (dst=r0). Warp 0 then requests I2 (src0=r0).
//     I2 must NOT issue until wb of I1 arrives (EXEC_LATENCY cycles).
//
//   Test 2 — Two-warp latency hiding
//     Warp 0 issues I1 (dst=r0). Warp 1 issues its own non-dependent instr.
//     While warp 0's wb is in-flight, warp 1 can keep issuing.
//
//   Test 3 — Round-robin fairness
//     All 4 warps have non-dependent instructions.
//     Scheduler must visit each warp in round-robin order.
//
// Extension 1: final block writes sim_stats.txt for Python perf_sweep.py.
// ============================================================================

module tb_mini_sm_phase4
    import simt_alu_pkg::*;
#(
    parameter int LANES        = simt_alu_pkg::LANES,
    parameter int DATA_WIDTH   = simt_alu_pkg::DATA_WIDTH,
    parameter int WARPS        = simt_alu_pkg::WARPS,
    parameter int REGS         = simt_alu_pkg::REGS,
    parameter int EXEC_LATENCY = simt_alu_pkg::EXEC_LATENCY,
    parameter int PC_W         = simt_alu_pkg::PC_W,
    // Extension 1 sweep plusargs (set at sim invocation)
    parameter string STATS_FILE = "sim_stats.txt"
);

    // -----------------------------------------------------------------------
    // PHASE A: Clock / Reset
    // -----------------------------------------------------------------------
    logic clk = 1'b0;
    initial forever #5 clk <= ~clk;

    // -----------------------------------------------------------------------
    // PHASE B: DUT Interface Signals
    // -----------------------------------------------------------------------
    logic rst;

    // Base Phase 4 inputs
    logic [WARPS-1:0]                            warp_has_instr;
    instr_meta_t [WARPS-1:0]                     warp_instr;
    logic [WARPS-1:0][LANES-1:0][DATA_WIDTH-1:0] warp_a;
    logic [WARPS-1:0][LANES-1:0][DATA_WIDTH-1:0] warp_b;

    // Extension 2 inputs (tied off — divergence test is in tb_divergence_phase4)
    logic [WARPS-1:0]             warp_is_branch    = '0;
    logic [WARPS-1:0][LANES-1:0] warp_branch_cond  = '0;
    logic [WARPS-1:0][PC_W-1:0]  warp_reconverge_pc= '0;
    logic [WARPS-1:0]            warp_path_done    = '0;

    // Debug outputs
    logic                  issue_valid;
    logic [WARP_ID_W-1:0] issue_warp_id;
    logic                  wb_valid;
    logic [WARP_ID_W-1:0] wb_warp_id;

    // Extension 2 status (unused in this TB)
    logic [WARPS-1:0][LANES-1:0] warp_active_mask;
    logic [WARPS-1:0]            warp_diverged;

    // Extension 1: Performance counter outputs
    logic [31:0] cycle_count;
    logic [31:0] issue_count;
    logic [31:0] stall_data_hazard;
    logic [31:0] stall_structural;
    logic [31:0] stall_memory_latency;
    logic [31:0] stall_no_ready_warp;
    logic [31:0] cycles_with_issue;
    logic [31:0] wb_count;
    logic [31:0] total_diverge_events;
    logic [31:0] masked_thread_cycles;

    // ALU result (not checked in this TB)
    logic [LANES-1:0][DATA_WIDTH-1:0] result;
    logic [LANES-1:0]                 zero_l, pos_l, neg_l;

    // -----------------------------------------------------------------------
    // PHASE D: Instantiate DUT
    // -----------------------------------------------------------------------
    mini_sm_top #(
        .LANES       (LANES),
        .DATA_WIDTH  (DATA_WIDTH),
        .WARPS       (WARPS),
        .REGS        (REGS),
        .EXEC_LATENCY(EXEC_LATENCY),
        .PC_W        (PC_W)
    ) DUT (.*);

    // -----------------------------------------------------------------------
    // Helper tasks / functions
    // -----------------------------------------------------------------------
    task automatic clear_all_warps();
        for (int w = 0; w < WARPS; w++) begin
            warp_has_instr[w] = 1'b0;
            warp_instr[w]     = '0;
            for (int l = 0; l < LANES; l++) begin
                warp_a[w][l] = '0;
                warp_b[w][l] = '0;
            end
        end
    endtask

    function automatic instr_meta_t make_instr(
        input logic [WARP_ID_W-1:0] wid,
        input logic [REG_ID_W-1:0]  s0, s1, d,
        input logic                  has_d
    );
        instr_meta_t m;
        m.warp_id  = wid;
        m.src0     = s0;
        m.src1     = s1;
        m.dst      = d;
        m.has_dst  = has_d;
        m.sel      = 3'b000; // ADD
        m.lane_mask= '1;
        return m;
    endfunction

    task automatic wait_issue(
        input  logic [WARP_ID_W-1:0] expected_wid,
        input  int                    timeout_cycles,
        output logic                  ok
    );
        ok = 1'b0;
        for (int t = 0; t < timeout_cycles; t++) begin
            @(posedge clk);
            if (issue_valid && issue_warp_id == expected_wid) begin
                ok = 1'b1;
                return;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // PHASE F/G/H: Stimulus + Checking
    // -----------------------------------------------------------------------
    initial begin : run_tests
        automatic int errors = 0;

        // Reset
        rst = 1'b0;
        clear_all_warps();
        @(negedge clk);
        rst = 1'b1;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        // ===================================================================
        // TEST 1: Single-warp RAW stall
        // ===================================================================
        $display("==== TEST 1: Single-warp RAW stall ====");
        begin
            logic ok;
            int   t_issue1, t_issue2;

            warp_has_instr[0] = 1'b1;
            warp_instr[0]     = make_instr(0, 4'd1, 4'd2, 4'd0, 1'b1);
            for (int l = 0; l < LANES; l++) begin
                warp_a[0][l] = 32'(l + 1);
                warp_b[0][l] = 32'(l + 2);
            end

            wait_issue(0, 10, ok);
            if (!ok) begin
                $error("TEST1: I1 never issued"); errors++;
            end else begin
                t_issue1 = $time;
                $display("  I1 issued at t=%0t", $time);
            end

            // Switch to I2 (RAW: reads r0 which is now busy)
            warp_instr[0] = make_instr(0, 4'd0, 4'd4, 4'd3, 1'b1);

            // I2 must stay blocked for at least EXEC_LATENCY-1 more cycles
            begin
                automatic int blocked = 0;
                repeat (EXEC_LATENCY - 1) begin
                    @(posedge clk);
                    if (issue_valid && issue_warp_id == 0) begin
                        $error("TEST1: I2 issued too early — RAW violated at t=%0t", $time);
                        errors++;
                    end else blocked++;
                end
                $display("  I2 correctly blocked for %0d cycles", blocked);
            end

            wait_issue(0, EXEC_LATENCY + 4, ok);
            if (!ok) begin
                $error("TEST1: I2 never issued after wb cleared hazard"); errors++;
            end else begin
                t_issue2 = $time;
                $display("  I2 issued at t=%0t (gap=%0t ns)", $time, t_issue2 - t_issue1);
            end

            warp_has_instr[0] = 1'b0;
            repeat (EXEC_LATENCY + 2) @(posedge clk);
        end

        // ===================================================================
        // TEST 2: Two-warp latency hiding
        // ===================================================================
        $display("==== TEST 2: Two-warp latency hiding ====");
        begin
            logic ok;
            int   w1_issues;
            w1_issues = 0;

            warp_has_instr[0] = 1'b1;
            warp_instr[0]     = make_instr(0, 4'd1, 4'd2, 4'd0, 1'b1);
            warp_has_instr[1] = 1'b1;
            warp_instr[1]     = make_instr(1, 4'd9, 4'd10, 4'd8, 1'b1);
            for (int l = 0; l < LANES; l++) begin
                warp_a[0][l] = 32'(l + 10); warp_b[0][l] = 32'(l + 20);
                warp_a[1][l] = 32'(l + 30); warp_b[1][l] = 32'(l + 40);
            end

            wait_issue(0, 10, ok);
            if (!ok) begin $error("TEST2: Warp 0 I1 never issued"); errors++; end
            else          $display("  Warp 0 I1 issued at t=%0t", $time);

            // Switch warp 0 to I2 (RAW on r0)
            warp_instr[0] = make_instr(0, 4'd0, 4'd4, 4'd3, 1'b1);

            repeat (EXEC_LATENCY) begin
                @(posedge clk);
                if (issue_valid && issue_warp_id == 1'b1) w1_issues++;
                if (issue_valid && issue_warp_id == 1'b0) begin
                    $error("TEST2: Warp 0 issued during stall window (RAW violated)");
                    errors++;
                end
            end

            if (w1_issues == 0) begin
                $error("TEST2: No latency hiding — warp 1 never issued while warp 0 stalled");
                errors++;
            end else
                $display("  Warp 1 issued %0d time(s) while warp 0 stalled — OK", w1_issues);

            wait_issue(0, EXEC_LATENCY + 4, ok);
            if (!ok) begin $error("TEST2: Warp 0 I2 never issued"); errors++; end
            else          $display("  Warp 0 I2 issued at t=%0t", $time);

            warp_has_instr[0] = 1'b0;
            warp_has_instr[1] = 1'b0;
            repeat (EXEC_LATENCY + 2) @(posedge clk);
        end

        // ===================================================================
        // TEST 3: Round-robin fairness
        // ===================================================================
        $display("==== TEST 3: Round-robin fairness ====");
        begin
            int observed[8];
            int rr_errors;
            rr_errors = 0;

            for (int w = 0; w < WARPS; w++) begin
                warp_has_instr[w] = 1'b1;
                warp_instr[w]     = make_instr(
                    WARP_ID_W'(w),
                    REG_ID_W'(w*4+1), REG_ID_W'(w*4+2), REG_ID_W'(w*4),
                    1'b1);
                for (int l = 0; l < LANES; l++) begin
                    warp_a[w][l] = 32'(w*100 + l);
                    warp_b[w][l] = 32'(w*100 + l + 1);
                end
            end

            for (int i = 0; i < 8; i++) begin
                logic found;
                found = 1'b0;
                for (int t = 0; t < 10 && !found; t++) begin
                    @(posedge clk);
                    if (issue_valid) begin
                        observed[i] = int'(issue_warp_id);
                        found = 1'b1;
                        $display("  Issue %0d: warp %0d", i, observed[i]);
                    end
                end
                if (!found) begin
                    $error("TEST3: Issue %0d never fired", i); errors++; rr_errors++;
                    observed[i] = -1;
                end
            end

            // Verify consecutive issues step by +1 mod WARPS
            for (int i = 1; i < 8; i++) begin
                if (observed[i-1] >= 0 && observed[i] >= 0) begin
                    int exp;
                    exp = (observed[i-1] + 1) % WARPS;
                    if (observed[i] !== exp) begin
                        $error("TEST3: After warp %0d expected warp %0d, got warp %0d",
                               observed[i-1], exp, observed[i]);
                        errors++; rr_errors++;
                    end
                end
            end

            if (rr_errors == 0)
                $display("  Round-robin order verified across 8 issues: PASS");

            for (int w = 0; w < WARPS; w++) warp_has_instr[w] = 1'b0;
            repeat (EXEC_LATENCY + 2) @(posedge clk);
        end

        // ===================================================================
        // SUMMARY
        // ===================================================================
        $display("========================================");
        $display("PHASE 4 MINI-SM SUMMARY");
        $display("  Total errors    : %0d", errors);
        $display("  cycle_count     : %0d", cycle_count);
        $display("  issue_count     : %0d", issue_count);
        $display("  stall_data_haz  : %0d", stall_data_hazard);
        $display("  stall_no_warp   : %0d", stall_no_ready_warp);
        $display("  cycles_issuing  : %0d", cycles_with_issue);
        if (errors == 0) $display("  RESULT          : PASS");
        else             $display("  RESULT          : FAIL");
        $display("========================================");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Extension 1: Stats file dump (runs at end of simulation)
    // -----------------------------------------------------------------------
    final begin
        int fd;
        string fname;
        // Allow stats file path to be overridden via plusarg: +stats_file=<path>
        if (!$value$plusargs("stats_file=%s", fname))
            fname = STATS_FILE;
        fd = $fopen(fname, "w");
        if (fd != 0) begin
            $fwrite(fd, "cycles=%0d\n",           cycle_count);
            $fwrite(fd, "instructions=%0d\n",     issue_count);
            $fwrite(fd, "stall_data=%0d\n",       stall_data_hazard);
            $fwrite(fd, "stall_structural=%0d\n", stall_structural);
            $fwrite(fd, "stall_memory=%0d\n",     stall_memory_latency);
            $fwrite(fd, "stall_no_warp=%0d\n",    stall_no_ready_warp);
            $fwrite(fd, "cycles_issuing=%0d\n",   cycles_with_issue);
            $fwrite(fd, "wb_count=%0d\n",         wb_count);
            $fclose(fd);
            $display("[stats] Wrote %s", fname);
        end else begin
            $display("[stats] WARNING: could not open %s", fname);
        end
    end

endmodule
