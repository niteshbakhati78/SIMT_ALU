`timescale 1ns/1ps
// ============================================================================
// tb_perf_sweep.sv — Steady-state IPC sweep testbench
//
// All WARPS warps issue self-dependent instructions:  r0 <- r0 + r1
// This maximises RAW stalls, forcing warps to hide each other's latency.
//
// IPC theory (EXEC_LATENCY >= WARPS):
//   IPC ≈ WARPS / EXEC_LATENCY
//
// IPC theory (EXEC_LATENCY < WARPS):
//   IPC ≈ 1.0  (fully hides latency)
//
// The testbench runs for enough cycles to reach steady state, then writes
// stats via the +stats_file=<path> plusarg (same format as tb_mini_sm_phase4).
// ============================================================================

module tb_perf_sweep
    import simt_alu_pkg::*;
#(
    parameter int LANES        = simt_alu_pkg::LANES,
    parameter int DATA_WIDTH   = simt_alu_pkg::DATA_WIDTH,
    parameter int WARPS        = simt_alu_pkg::WARPS,
    parameter int REGS         = simt_alu_pkg::REGS,
    parameter int EXEC_LATENCY = simt_alu_pkg::EXEC_LATENCY,
    parameter int PC_W         = simt_alu_pkg::PC_W,
    parameter string STATS_FILE = "sim_stats.txt"
);

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    logic clk = 1'b0;
    initial forever #5 clk <= ~clk;

    // -----------------------------------------------------------------------
    // DUT interface
    // -----------------------------------------------------------------------
    logic rst;

    logic [WARPS-1:0]                            warp_has_instr;
    instr_meta_t [WARPS-1:0]                     warp_instr;
    logic [WARPS-1:0][LANES-1:0][DATA_WIDTH-1:0] warp_a;
    logic [WARPS-1:0][LANES-1:0][DATA_WIDTH-1:0] warp_b;

    // Extension 2 — tied off (no divergence in this sweep)
    logic [WARPS-1:0]             warp_is_branch    = '0;
    logic [WARPS-1:0][LANES-1:0] warp_branch_cond  = '0;
    logic [WARPS-1:0][PC_W-1:0]  warp_reconverge_pc= '0;
    logic [WARPS-1:0]            warp_path_done    = '0;

    // Outputs
    logic                  issue_valid;
    logic [WARP_ID_W-1:0] issue_warp_id;
    logic                  wb_valid;
    logic [WARP_ID_W-1:0] wb_warp_id;
    logic [WARPS-1:0][LANES-1:0] warp_active_mask;
    logic [WARPS-1:0]            warp_diverged;

    // Performance counters
    logic [31:0] cycle_count, issue_count;
    logic [31:0] stall_data_hazard, stall_structural, stall_memory_latency, stall_no_ready_warp;
    logic [31:0] cycles_with_issue, wb_count;
    logic [31:0] total_diverge_events, masked_thread_cycles;

    logic [LANES-1:0][DATA_WIDTH-1:0] result;
    logic [LANES-1:0]                 zero_l, pos_l, neg_l;

    // -----------------------------------------------------------------------
    // DUT instantiation
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
    // Build a self-dependent instruction:  r0 <- r0 + r1  (warp w)
    // src0=r0 creates a RAW stall against the previous issue for the same warp.
    // -----------------------------------------------------------------------
    function automatic instr_meta_t make_dep_instr(
        input logic [WARP_ID_W-1:0] wid
    );
        instr_meta_t m = '0;
        m.warp_id  = wid;
        m.src0     = 4'd0;  // r0 — RAW source
        m.src1     = 4'd1;  // r1 — never written, always clear
        m.dst      = 4'd0;  // r0 — keeps the hazard alive
        m.has_dst  = 1'b1;
        m.sel      = 3'b000; // ADD
        m.lane_mask= '1;
        return m;
    endfunction

    // -----------------------------------------------------------------------
    // Stimulus
    // -----------------------------------------------------------------------
    // Run long enough to cover: ramp-up (WARPS cycles) + many steady-state periods.
    // One period ≈ max(WARPS, EXEC_LATENCY) cycles.
    localparam int RUN_CYCLES = EXEC_LATENCY * WARPS * 6 + 200;

    initial begin : stimulus
        rst = 1'b1;
        warp_has_instr = '0;
        warp_instr     = '0;
        warp_a         = '0;
        warp_b         = '0;

        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // Load all warps with self-dependent instructions
        for (int w = 0; w < WARPS; w++) begin
            warp_has_instr[w] = 1'b1;
            warp_instr[w]     = make_dep_instr(WARP_ID_W'(w));
            for (int l = 0; l < LANES; l++) begin
                warp_a[w][l] = 32'(w * 8 + l + 1);
                warp_b[w][l] = 32'(1);
            end
        end

        // Run to steady state
        repeat (RUN_CYCLES) @(posedge clk);

        $finish;
    end

    // -----------------------------------------------------------------------
    // Stats file dump (triggered by $finish above)
    // -----------------------------------------------------------------------
    final begin
        int fd;
        string fname;
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
        end
    end

endmodule
