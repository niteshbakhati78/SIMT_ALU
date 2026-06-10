// mini_sm_top.sv — Phase 4 Mini-SM Integration Top
//                  + Extension 1 (Cycle-Accurate Performance Counters)
//                  + Extension 2 (PDOM Divergence Stack)
//
// Wires together:
//   warp_table     — per-warp state (READY/STALLED)
//   scoreboard     — per-warp register busy tracking (RAW hazards)
//   warp_scheduler — round-robin warp selection
//   exec_pipe      — fixed-latency pipeline, generates writeback events
//   simt_alu       — existing SIMT ALU (combinational datapath)
//   pdom_ctrl[W]   — per-warp PDOM reconvergence stack (Extension 2)
//
// Extension 1 adds: cycle_count, classified stall counters, cycles_with_issue.
// Extension 2 adds: per-warp PDOM stack, active_mask override to the ALU,
//                   diverge event counter, masked_thread_cycles counter.
//
// All Extension 2 inputs default to '0 so the Phase 4 testbench (which does
// not drive them) continues to compile and run correctly.

module mini_sm_top
    import simt_alu_pkg::*;
#(
    parameter int LANES        = simt_alu_pkg::LANES,
    parameter int DATA_WIDTH   = simt_alu_pkg::DATA_WIDTH,
    parameter int WARPS        = simt_alu_pkg::WARPS,
    parameter int REGS         = simt_alu_pkg::REGS,
    parameter int EXEC_LATENCY = simt_alu_pkg::EXEC_LATENCY,
    parameter int PC_W         = simt_alu_pkg::PC_W,
    parameter int PDOM_DEPTH   = simt_alu_pkg::PDOM_DEPTH
)(
    input  logic clk,
    input  logic rst,

    // -----------------------------------------------------------------------
    // Per-warp instruction source (driven by testbench)
    // -----------------------------------------------------------------------
    input  logic [WARPS-1:0]                               warp_has_instr,
    input  instr_meta_t [WARPS-1:0]                        warp_instr,
    input  logic [WARPS-1:0][LANES-1:0][DATA_WIDTH-1:0]    warp_a,
    input  logic [WARPS-1:0][LANES-1:0][DATA_WIDTH-1:0]    warp_b,

    // -----------------------------------------------------------------------
    // Extension 2: Branch divergence inputs (default = '0, no divergence)
    // -----------------------------------------------------------------------
    input  logic [WARPS-1:0]             warp_is_branch    /* = '0 */,
    input  logic [WARPS-1:0][LANES-1:0] warp_branch_cond  /* = '0 */,
    input  logic [WARPS-1:0][PC_W-1:0]  warp_reconverge_pc/* = '0 */,
    input  logic [WARPS-1:0]            warp_path_done    /* = '0 */,

    // -----------------------------------------------------------------------
    // Debug / monitoring outputs
    // -----------------------------------------------------------------------
    output logic                  issue_valid,
    output logic [WARP_ID_W-1:0] issue_warp_id,
    output logic                  wb_valid,
    output logic [WARP_ID_W-1:0] wb_warp_id,

    // Extension 2: Per-warp PDOM status
    output logic [WARPS-1:0][LANES-1:0] warp_active_mask,
    output logic [WARPS-1:0]            warp_diverged,

    // -----------------------------------------------------------------------
    // Extension 1: Cycle-accurate performance counters
    // -----------------------------------------------------------------------
    output logic [31:0] cycle_count,
    output logic [31:0] issue_count,          // total instructions issued
    output logic [31:0] stall_data_hazard,    // stall: scoreboard blocked issue
    output logic [31:0] stall_structural,     // stall: FU not available (future)
    output logic [31:0] stall_memory_latency, // stall: warp waiting on memory (future)
    output logic [31:0] stall_no_ready_warp,  // stall: no eligible warp at all
    output logic [31:0] cycles_with_issue,    // cycles where at least 1 warp issued
    output logic [31:0] wb_count,

    // Extension 2: Divergence counters
    output logic [31:0] total_diverge_events, // true divergence events (both masks nonzero)
    output logic [31:0] masked_thread_cycles, // thread-cycles lost to inactive masking

    // SIMT ALU result for the issued warp
    output logic [LANES-1:0][DATA_WIDTH-1:0] result,
    output logic [LANES-1:0]                 zero_l,
    output logic [LANES-1:0]                 pos_l,
    output logic [LANES-1:0]                 neg_l
);

    // -----------------------------------------------------------------------
    // Internal wires
    // -----------------------------------------------------------------------
    logic [WARPS-1:0] warp_ready;
    logic [WARPS-1:0] warp_can_issue;

    logic [WARPS-1:0][REG_ID_W-1:0] check_src0;
    logic [WARPS-1:0][REG_ID_W-1:0] check_src1;

    logic                  wb_has_dst;
    logic [REG_ID_W-1:0]  wb_dst_reg;
    logic [WARP_ID_W-1:0] wb_warp_id_int;

    assign wb_warp_id = wb_warp_id_int;

    // Extension 1: stall classification
    logic scoreboard_blocked;  // at least one eligible warp is blocked by scoreboard

    // -----------------------------------------------------------------------
    // Extract src regs from each warp's pending instruction
    // -----------------------------------------------------------------------
    always_comb begin
        for (int w = 0; w < WARPS; w++) begin
            check_src0[w] = warp_instr[w].src0;
            check_src1[w] = warp_instr[w].src1;
        end
    end

    // Extension 1: scoreboard_blocked = any ready+has_instr warp blocked by RAW
    always_comb begin
        scoreboard_blocked = 1'b0;
        for (int w = 0; w < WARPS; w++) begin
            if (warp_has_instr[w] && warp_ready[w] && !warp_can_issue[w])
                scoreboard_blocked = 1'b1;
        end
    end

    // -----------------------------------------------------------------------
    // Warp Table
    // -----------------------------------------------------------------------
    warp_table #(.WARPS(WARPS)) u_warp_table (
        .clk            (clk),
        .rst            (rst),
        .stall_warp     (1'b0),
        .stall_warp_id  ('0),
        .unblock_warp   (1'b0),
        .unblock_warp_id('0),
        .warp_ready     (warp_ready)
    );

    // -----------------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------------
    scoreboard #(.WARPS(WARPS), .REGS(REGS)) u_scoreboard (
        .clk           (clk),
        .rst           (rst),
        .issue_fire    (issue_valid),
        .issue_warp_id (issue_warp_id),
        .issue_src0    (warp_instr[issue_warp_id].src0),
        .issue_src1    (warp_instr[issue_warp_id].src1),
        .issue_dst     (warp_instr[issue_warp_id].dst),
        .issue_has_dst (warp_instr[issue_warp_id].has_dst),
        .wb_valid      (wb_valid),
        .wb_warp_id    (wb_warp_id_int),
        .wb_dst        (wb_dst_reg),
        .wb_has_dst    (wb_has_dst),
        .check_src0    (check_src0),
        .check_src1    (check_src1),
        .can_issue     (warp_can_issue)
    );

    // -----------------------------------------------------------------------
    // Warp Scheduler
    // -----------------------------------------------------------------------
    warp_scheduler #(.WARPS(WARPS)) u_warp_scheduler (
        .clk            (clk),
        .rst            (rst),
        .warp_ready     (warp_ready),
        .warp_can_issue (warp_can_issue),
        .warp_has_instr (warp_has_instr),
        .issue_valid    (issue_valid),
        .issue_warp_id  (issue_warp_id)
    );

    // -----------------------------------------------------------------------
    // Execution Pipeline
    // -----------------------------------------------------------------------
    exec_pipe #(
        .WARPS        (WARPS),
        .REGS         (REGS),
        .EXEC_LATENCY (EXEC_LATENCY)
    ) u_exec_pipe (
        .clk           (clk),
        .rst           (rst),
        .issue_fire    (issue_valid),
        .issue_warp_id (issue_warp_id),
        .issue_dst     (warp_instr[issue_warp_id].dst),
        .issue_has_dst (warp_instr[issue_warp_id].has_dst),
        .wb_valid      (wb_valid),
        .wb_warp_id    (wb_warp_id_int),
        .wb_dst        (wb_dst_reg),
        .wb_has_dst    (wb_has_dst)
    );

    // -----------------------------------------------------------------------
    // Extension 2: Per-warp PDOM Controllers
    // -----------------------------------------------------------------------
    logic [WARPS-1:0] pdom_stack_empty;
    logic [WARPS-1:0] pdom_stack_full;

    genvar gw;
    generate
        for (gw = 0; gw < WARPS; gw++) begin : GEN_PDOM
            pdom_ctrl #(
                .LANES(LANES),
                .PC_W (PC_W),
                .DEPTH(PDOM_DEPTH)
            ) u_pdom (
                .clk           (clk),
                .rst           (rst),
                .branch_fire   (issue_valid && warp_is_branch[gw]
                                && (issue_warp_id == WARP_ID_W'(gw))),
                .branch_cond   (warp_branch_cond[gw]),
                .reconverge_pc (warp_reconverge_pc[gw]),
                .path_done     (warp_path_done[gw]),
                .active_mask   (warp_active_mask[gw]),
                .stack_empty   (pdom_stack_empty[gw]),
                .stack_full    (pdom_stack_full[gw]),
                .diverged      (warp_diverged[gw])
            );
        end
    endgenerate

    // -----------------------------------------------------------------------
    // SIMT ALU — use PDOM active_mask instead of raw lane_mask
    // When no PDOM divergence (warp_is_branch='0, path_done='0), active_mask
    // stays all-ones so behavior is identical to the Phase 4 base design.
    // -----------------------------------------------------------------------
    logic [2:0]                       alu_sel;
    logic [LANES-1:0]                 alu_lane_mask;
    logic [LANES-1:0][DATA_WIDTH-1:0] alu_a, alu_b;
    logic                             alu_in_ready, alu_out_valid;

    always_comb begin
        alu_sel       = warp_instr[issue_warp_id].sel;
        alu_lane_mask = warp_active_mask[issue_warp_id]; // PDOM-controlled mask
        alu_a         = warp_a[issue_warp_id];
        alu_b         = warp_b[issue_warp_id];
    end

    simt_alu #(
        .DATA_WIDTH(DATA_WIDTH),
        .LANES     (LANES)
    ) u_simt_alu (
        .clk      (clk),
        .rst      (rst),
        .in_valid (issue_valid),
        .in_ready (alu_in_ready),
        .out_valid(alu_out_valid),
        .out_ready(1'b1),
        .sel      (alu_sel),
        .lane_mask(alu_lane_mask),
        .a        (alu_a),
        .b        (alu_b),
        .result   (result),
        .zero_l   (zero_l),
        .pos_l    (pos_l),
        .neg_l    (neg_l)
    );

    // -----------------------------------------------------------------------
    // Extension 1: Cycle-accurate performance counters
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count          <= '0;
            issue_count          <= '0;
            stall_data_hazard    <= '0;
            stall_structural     <= '0;
            stall_memory_latency <= '0;
            stall_no_ready_warp  <= '0;
            cycles_with_issue    <= '0;
            wb_count             <= '0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (issue_valid) begin
                issue_count       <= issue_count + 1;
                cycles_with_issue <= cycles_with_issue + 1;
            end

            if (wb_valid)
                wb_count <= wb_count + 1;

            // Stall classification (priority-based, one bucket per stall cycle)
            if (!issue_valid) begin
                if (scoreboard_blocked)
                    stall_data_hazard <= stall_data_hazard + 1;
                // stall_structural: no FU backpressure in Phase 4 (always 0)
                else if (1'b0)
                    stall_structural <= stall_structural + 1;
                // stall_memory_latency: no LSU in Phase 4 (always 0)
                else if (1'b0)
                    stall_memory_latency <= stall_memory_latency + 1;
                else
                    stall_no_ready_warp <= stall_no_ready_warp + 1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Extension 2: Divergence performance counters
    // -----------------------------------------------------------------------
    // then/else masks for the currently-issued branch (used to detect divergence)
    logic [LANES-1:0] issued_then_mask, issued_else_mask;
    always_comb begin
        issued_then_mask =  warp_branch_cond[issue_warp_id] & warp_active_mask[issue_warp_id];
        issued_else_mask = ~warp_branch_cond[issue_warp_id] & warp_active_mask[issue_warp_id];
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            total_diverge_events <= '0;
            masked_thread_cycles <= '0;
        end else begin
            // Count true divergence events (both paths have active threads)
            if (issue_valid && warp_is_branch[issue_warp_id]
                && (issued_then_mask != '0) && (issued_else_mask != '0))
                total_diverge_events <= total_diverge_events + 1;

            // Count thread-cycles wasted to masking across all diverged warps
            begin
                automatic logic [31:0] masked_this_cycle;
                masked_this_cycle = '0;
                for (int w = 0; w < WARPS; w++) begin
                    if (warp_diverged[w])
                        masked_this_cycle += 32'($countones(~warp_active_mask[w]));
                end
                masked_thread_cycles <= masked_thread_cycles + masked_this_cycle;
            end
        end
    end

endmodule
