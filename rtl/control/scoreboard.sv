// scoreboard.sv — Phase 4 Mini-SM
// Per-warp register busy table (RAW hazard detection).
//
// reg_busy_q[w][r] = 1 means register r of warp w has an in-flight write.
//
// can_issue[w] = 1 when neither src0 nor src1 of warp w's pending instruction
//                  is marked busy for that warp.
//
// Ordering when writeback and issue touch the same reg in the same cycle:
//   writeback clears first, then issue may set again.
//   This means a same-cycle wb+issue on the same dst re-marks it busy (correct).

module scoreboard
    import simt_alu_pkg::*;
#(
    parameter int WARPS = simt_alu_pkg::WARPS,
    parameter int REGS  = simt_alu_pkg::REGS
)(
    input  logic clk,
    input  logic rst,

    // Issue inputs: fired when the scheduler selects a warp
    input  logic                  issue_fire,
    input  logic [WARP_ID_W-1:0] issue_warp_id,
    input  logic [REG_ID_W-1:0]  issue_src0,
    input  logic [REG_ID_W-1:0]  issue_src1,
    input  logic [REG_ID_W-1:0]  issue_dst,
    input  logic                  issue_has_dst,

    // Writeback inputs: from exec_pipe, clears busy bit
    input  logic                  wb_valid,
    input  logic [WARP_ID_W-1:0] wb_warp_id,
    input  logic [REG_ID_W-1:0]  wb_dst,
    input  logic                  wb_has_dst,

    // Per-warp source registers to check (each warp's pending instruction)
    input  logic [WARPS-1:0][REG_ID_W-1:0] check_src0,
    input  logic [WARPS-1:0][REG_ID_W-1:0] check_src1,

    // can_issue[w] = 1 when warp w's pending instr has no RAW hazard
    output logic [WARPS-1:0] can_issue
);

    logic [REGS-1:0] reg_busy_q [WARPS];

    // -----------------------------------------------------------------------
    // Combinational: per-warp hazard check
    // -----------------------------------------------------------------------
    always_comb begin
        for (int w = 0; w < WARPS; w++) begin
            can_issue[w] = !(reg_busy_q[w][check_src0[w]] || reg_busy_q[w][check_src1[w]]);
        end
    end

    // -----------------------------------------------------------------------
    // Sequential: update busy bits
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int w = 0; w < WARPS; w++) begin
                reg_busy_q[w] <= '0;
            end
        end else begin
            // 1) Writeback clears busy first
            if (wb_valid && wb_has_dst) begin
                reg_busy_q[wb_warp_id][wb_dst] <= 1'b0;
            end
            // 2) Issue sets busy after (may re-set same reg if same cycle)
            if (issue_fire && issue_has_dst) begin
                reg_busy_q[issue_warp_id][issue_dst] <= 1'b1;
            end
        end
    end

endmodule
