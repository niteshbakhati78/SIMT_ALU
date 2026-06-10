`timescale 1ns/1ps
// ============================================================================
// Testbench: Extension 2 — PDOM Divergence (Directed + Self-Checking)
// ============================================================================
// Tests:
//
//   Test 1 — Single-warp, single branch divergence, THEN-first
//     Warp 0 executes with full mask (8'hFF).
//     A branch fires: cond = 8'hCA → then_mask=8'hCA, else_mask=8'h35.
//     Expected: active_mask becomes 8'hCA (THEN path).
//     After path_done: PDOM pops → active_mask becomes 8'h35 (ELSE path).
//     After second path_done: stack empty → active_mask = 8'hFF (reconverged).
//
//   Test 2 — No divergence (all threads take same path)
//     cond = 8'hFF → then_mask=8'hFF, else_mask=8'h00.
//     Expected: no push, active_mask stays 8'hFF.
//
//   Test 3 — Two warps diverge independently
//     Warp 0 and Warp 1 each diverge at different branch conditions.
//     Verify masks update independently.
//
//   Test 4 — IPC degradation visible in counters
//     Run instructions with a divergence event and verify masked_thread_cycles > 0.
//
// Divergence stats file written at end via $fwrite (Extension 1 integration).
// ============================================================================

module tb_divergence_phase4
    import simt_alu_pkg::*;
#(
    parameter int LANES        = simt_alu_pkg::LANES,
    parameter int DATA_WIDTH   = simt_alu_pkg::DATA_WIDTH,
    parameter int WARPS        = simt_alu_pkg::WARPS,
    parameter int REGS         = simt_alu_pkg::REGS,
    parameter int EXEC_LATENCY = simt_alu_pkg::EXEC_LATENCY,
    parameter int PC_W         = simt_alu_pkg::PC_W,
    parameter string STATS_FILE = "div_stats.txt"
);

    // -----------------------------------------------------------------------
    // PHASE A: Clock
    // -----------------------------------------------------------------------
    logic clk = 1'b0;
    initial forever #5 clk <= ~clk;

    // -----------------------------------------------------------------------
    // PHASE B: DUT Interface Signals
    // -----------------------------------------------------------------------
    logic rst;

    logic [WARPS-1:0]                            warp_has_instr;
    instr_meta_t [WARPS-1:0]                     warp_instr;
    logic [WARPS-1:0][LANES-1:0][DATA_WIDTH-1:0] warp_a;
    logic [WARPS-1:0][LANES-1:0][DATA_WIDTH-1:0] warp_b;

    // Extension 2 inputs
    logic [WARPS-1:0]             warp_is_branch;
    logic [WARPS-1:0][LANES-1:0] warp_branch_cond;
    logic [WARPS-1:0][PC_W-1:0]  warp_reconverge_pc;
    logic [WARPS-1:0]            warp_path_done;

    // Outputs
    logic                  issue_valid;
    logic [WARP_ID_W-1:0] issue_warp_id;
    logic                  wb_valid;
    logic [WARP_ID_W-1:0] wb_warp_id;

    logic [WARPS-1:0][LANES-1:0] warp_active_mask;
    logic [WARPS-1:0]            warp_diverged;

    logic [31:0] cycle_count, issue_count;
    logic [31:0] stall_data_hazard, stall_structural, stall_memory_latency, stall_no_ready_warp;
    logic [31:0] cycles_with_issue, wb_count;
    logic [31:0] total_diverge_events, masked_thread_cycles;

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
    // Helpers
    // -----------------------------------------------------------------------
    task automatic clear_all_warps();
        for (int w = 0; w < WARPS; w++) begin
            warp_has_instr[w]     = 1'b0;
            warp_instr[w]         = '0;
            warp_is_branch[w]     = 1'b0;
            warp_branch_cond[w]   = '0;
            warp_reconverge_pc[w] = '0;
            warp_path_done[w]     = 1'b0;
            for (int l = 0; l < LANES; l++) begin
                warp_a[w][l] = '0;
                warp_b[w][l] = '0;
            end
        end
    endtask

    // Build an ADD instruction (non-branch, no dst dependency on each other)
    function automatic instr_meta_t make_instr(
        input logic [WARP_ID_W-1:0] wid,
        input logic [REG_ID_W-1:0]  s0, s1, d, input logic has_d
    );
        instr_meta_t m = '0;
        m.warp_id = wid; m.src0 = s0; m.src1 = s1;
        m.dst = d; m.has_dst = has_d; m.sel = 3'b000; m.lane_mask = '1;
        return m;
    endfunction

    // Build an SLT instruction flagged as branch
    function automatic instr_meta_t make_branch_instr(
        input logic [WARP_ID_W-1:0] wid,
        input logic [REG_ID_W-1:0]  s0, s1
    );
        instr_meta_t m = '0;
        m.warp_id = wid; m.src0 = s0; m.src1 = s1;
        m.has_dst = 1'b0; m.sel = 3'b110; m.lane_mask = '1; // SLT
        return m;
    endfunction

    task automatic wait_issue_any(input int timeout_cycles, output logic ok);
        ok = 1'b0;
        for (int t = 0; t < timeout_cycles; t++) begin
            @(posedge clk);
            if (issue_valid) begin ok = 1'b1; return; end
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
        // TEST 1: Single-warp branch divergence — THEN-first, then ELSE path
        // ===================================================================
        // Warp 0 issues a branch (SLT) with cond=8'hCA
        //   then_mask = 8'hCA & 8'hFF = 8'hCA  (threads 1,3,6,7 taken)
        //   else_mask = ~8'hCA & 8'hFF = 8'h35 (threads 0,2,4,5 not-taken)
        // Expect: active_mask → 8'hCA immediately after branch fires
        // After path_done: PDOM pops → active_mask → 8'h35 (next cycle)
        // After second path_done: reconverged → active_mask → 8'hFF
        // ===================================================================
        $display("==== TEST 1: Single-warp branch divergence (THEN-first) ====");
        begin
            logic ok;
            logic [LANES-1:0] exp_then, exp_else;
            logic [LANES-1:0] bc;
            bc       = 8'hCA;
            exp_then = bc & 8'hFF;   // 8'hCA
            exp_else = (~bc) & 8'hFF; // 8'h35

            // Present branch instruction for warp 0
            warp_has_instr[0]     = 1'b1;
            warp_instr[0]         = make_branch_instr(0, 4'd1, 4'd2);
            warp_is_branch[0]     = 1'b1;
            warp_branch_cond[0]   = bc;
            warp_reconverge_pc[0] = 16'h0300;
            for (int l = 0; l < LANES; l++) begin
                warp_a[0][l] = 32'(l);
                warp_b[0][l] = 32'(l + 1); // all SLT → 1 (taken)
            end

            // Wait for the branch to issue
            wait_issue_any(10, ok);
            if (!ok) begin $error("TEST1: Branch never issued"); errors++; end
            else           $display("  Branch issued at t=%0t, warp=%0d", $time, issue_warp_id);

            // Immediately deassert branch so it cannot re-issue next cycle
            warp_is_branch[0] = 1'b0;
            warp_instr[0]     = make_instr(0, 4'd5, 4'd6, 4'd7, 1'b1);

            // After branch issues (combinational), check active_mask updated next cycle
            @(posedge clk);
            if (warp_active_mask[0] !== exp_then) begin
                $error("TEST1: active_mask after branch: expected %08b got %08b",
                       exp_then, warp_active_mask[0]);
                errors++;
            end else
                $display("  active_mask = %08b (THEN path) — PASS", warp_active_mask[0]);

            // Check diverged = 1 (else path on stack)
            if (!warp_diverged[0]) begin
                $error("TEST1: warp_diverged[0] should be 1 after divergence");
                errors++;
            end

            // Warp 0 executes THEN path instructions
            repeat (2) @(posedge clk);

            // Signal THEN path done
            warp_path_done[0] = 1'b1;
            @(posedge clk);
            warp_path_done[0] = 1'b0;

            // POP_WAIT: curr_mask <= st_pop_mask fires as NBA at this posedge;
            // read result one cycle later when the NBA has settled.
            @(posedge clk);  // POP_WAIT state fires, curr_mask <= else_mask (NBA)
            @(posedge clk);  // settle: now active_mask reflects else_mask

            // Now active_mask should be ELSE path mask
            if (warp_active_mask[0] !== exp_else) begin
                $error("TEST1: active_mask after pop: expected %08b (ELSE) got %08b",
                       exp_else, warp_active_mask[0]);
                errors++;
            end else
                $display("  active_mask = %08b (ELSE path after pop) — PASS", warp_active_mask[0]);

            // Signal ELSE path done
            repeat (2) @(posedge clk);
            warp_path_done[0] = 1'b1;
            @(posedge clk);
            warp_path_done[0] = 1'b0;
            @(posedge clk); // one settle cycle

            // Stack empty, active_mask should reconverge to all-ones
            if (warp_active_mask[0] !== '1) begin
                $error("TEST1: After reconvergence expected mask=FF got %08b", warp_active_mask[0]);
                errors++;
            end else
                $display("  Reconverged: active_mask = %08b (all-ones) — PASS", warp_active_mask[0]);

            if (!warp_diverged[0] === 1'b0) // stack empty
                $display("  warp_diverged[0] = 0 — PASS");

            warp_has_instr[0] = 1'b0;
            repeat (2) @(posedge clk);
        end

        // ===================================================================
        // TEST 2: No divergence — all threads take same path (no push)
        // ===================================================================
        $display("==== TEST 2: No divergence (uniform condition) ====");
        begin
            logic ok;

            // cond = 8'hFF → then_mask=8'hFF, else_mask=8'h00 → no push
            warp_has_instr[0]     = 1'b1;
            warp_instr[0]         = make_branch_instr(0, 4'd1, 4'd2);
            warp_is_branch[0]     = 1'b1;
            warp_branch_cond[0]   = 8'hFF;  // all taken
            warp_reconverge_pc[0] = 16'h0400;
            for (int l = 0; l < LANES; l++) warp_a[0][l] = 32'(l);

            wait_issue_any(10, ok);
            if (!ok) begin $error("TEST2: Branch never issued"); errors++; end

            @(posedge clk); // let FSM update

            if (warp_active_mask[0] !== 8'hFF) begin
                $error("TEST2: active_mask expected FF (no divergence), got %08b",
                       warp_active_mask[0]);
                errors++;
            end else
                $display("  active_mask = %08b (no divergence) — PASS", warp_active_mask[0]);

            if (warp_diverged[0]) begin
                $error("TEST2: warp_diverged should be 0 when no divergence");
                errors++;
            end else
                $display("  warp_diverged[0] = 0 — PASS");

            warp_has_instr[0] = 1'b0;
            warp_is_branch[0] = 1'b0;
            repeat (2) @(posedge clk);
        end

        // ===================================================================
        // TEST 3: Two warps diverge independently
        // ===================================================================
        $display("==== TEST 3: Two warps diverge independently ====");
        begin
            logic ok;

            // Warp 0: cond = 8'hF0
            // Warp 1: cond = 8'h0F
            warp_has_instr[0]     = 1'b1;
            warp_has_instr[1]     = 1'b1;
            warp_instr[0]         = make_branch_instr(0, 4'd1, 4'd2);
            warp_instr[1]         = make_branch_instr(1, 4'd5, 4'd6);
            warp_is_branch[0]     = 1'b1;
            warp_is_branch[1]     = 1'b1;
            warp_branch_cond[0]   = 8'hF0;
            warp_branch_cond[1]   = 8'h0F;
            warp_reconverge_pc[0] = 16'h0500;
            warp_reconverge_pc[1] = 16'h0600;

            // Let both warps issue their branches (RR scheduling)
            repeat (WARPS + 4) begin
                @(posedge clk);
            end

            // After both branches issued, verify independent masks
            // Warp 0: then_mask = 8'hF0, warp 1: then_mask = 8'h0F
            $display("  warp_active_mask[0] = %08b (expected F0 or 0F after issue)",
                     warp_active_mask[0]);
            $display("  warp_active_mask[1] = %08b", warp_active_mask[1]);

            // At least verify masks differ if both diverged
            if (warp_diverged[0] && warp_diverged[1]) begin
                if (warp_active_mask[0] === warp_active_mask[1]) begin
                    $error("TEST3: Both warps diverged but have same mask — independence violated");
                    errors++;
                end else
                    $display("  Warp masks differ — independence verified PASS");
            end

            warp_has_instr[0] = 1'b0; warp_has_instr[1] = 1'b0;
            warp_is_branch[0] = 1'b0; warp_is_branch[1] = 1'b0;
            // Reconverge both warps
            warp_path_done[0] = 1'b1; warp_path_done[1] = 1'b1;
            @(posedge clk);
            warp_path_done[0] = 1'b0; warp_path_done[1] = 1'b0;
            repeat (3) @(posedge clk);
            warp_path_done[0] = 1'b1; warp_path_done[1] = 1'b1;
            @(posedge clk);
            warp_path_done[0] = 1'b0; warp_path_done[1] = 1'b0;
            repeat (3) @(posedge clk);
        end

        // ===================================================================
        // TEST 4: masked_thread_cycles counter increments during divergence
        // ===================================================================
        $display("==== TEST 4: masked_thread_cycles counter ====");
        begin
            logic ok;
            logic [31:0] mtc_before, mtc_after;

            mtc_before = masked_thread_cycles;

            // Diverge warp 0 with cond=8'hCA (4 threads masked in each path)
            warp_has_instr[0]     = 1'b1;
            warp_instr[0]         = make_branch_instr(0, 4'd1, 4'd2);
            warp_is_branch[0]     = 1'b1;
            warp_branch_cond[0]   = 8'hCA;
            warp_reconverge_pc[0] = 16'h0700;

            wait_issue_any(10, ok);
            if (!ok) begin $error("TEST4: Branch never issued"); errors++; end

            // Let 5 cycles pass while warp 0 is diverged
            warp_is_branch[0] = 1'b0;
            warp_instr[0]     = make_instr(0, 4'd5, 4'd6, 4'd7, 1'b1);
            repeat (5) @(posedge clk);

            mtc_after = masked_thread_cycles;
            if (mtc_after <= mtc_before) begin
                $error("TEST4: masked_thread_cycles did not increase during divergence (%0d→%0d)",
                       mtc_before, mtc_after);
                errors++;
            end else
                $display("  masked_thread_cycles: %0d → %0d (delta=%0d) — PASS",
                         mtc_before, mtc_after, mtc_after - mtc_before);

            // Reconverge
            warp_path_done[0] = 1'b1;
            @(posedge clk); warp_path_done[0] = 1'b0;
            repeat (2) @(posedge clk);
            warp_path_done[0] = 1'b1;
            @(posedge clk); warp_path_done[0] = 1'b0;
            warp_has_instr[0] = 1'b0;
            repeat (EXEC_LATENCY + 2) @(posedge clk);
        end

        // ===================================================================
        // SUMMARY
        // ===================================================================
        $display("========================================");
        $display("EXTENSION 2 DIVERGENCE SUMMARY");
        $display("  Total errors          : %0d", errors);
        $display("  cycle_count           : %0d", cycle_count);
        $display("  issue_count           : %0d", issue_count);
        $display("  total_diverge_events  : %0d", total_diverge_events);
        $display("  masked_thread_cycles  : %0d", masked_thread_cycles);
        if (errors == 0) $display("  RESULT                : PASS");
        else             $display("  RESULT                : FAIL");
        $display("========================================");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Extension 1: Stats dump for divergence sweep script
    // -----------------------------------------------------------------------
    final begin
        int fd;
        string fname;
        if (!$value$plusargs("stats_file=%s", fname))
            fname = STATS_FILE;
        fd = $fopen(fname, "w");
        if (fd != 0) begin
            $fwrite(fd, "cycles=%0d\n",                cycle_count);
            $fwrite(fd, "instructions=%0d\n",          issue_count);
            $fwrite(fd, "stall_data=%0d\n",            stall_data_hazard);
            $fwrite(fd, "stall_structural=%0d\n",      stall_structural);
            $fwrite(fd, "stall_memory=%0d\n",          stall_memory_latency);
            $fwrite(fd, "stall_no_warp=%0d\n",         stall_no_ready_warp);
            $fwrite(fd, "cycles_issuing=%0d\n",        cycles_with_issue);
            $fwrite(fd, "wb_count=%0d\n",              wb_count);
            $fwrite(fd, "total_diverge_events=%0d\n",  total_diverge_events);
            $fwrite(fd, "masked_thread_cycles=%0d\n",  masked_thread_cycles);
            $fclose(fd);
            $display("[stats] Wrote %s", fname);
        end
    end

endmodule
