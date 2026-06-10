// warp_table.sv — Phase 4 Mini-SM
// Tracks per-warp state (READY / STALLED) and exposes warp_ready[] to
// the scheduler.
//
// Priority rule when stall and unblock both fire same cycle:
//   unblock wins (warp returns to READY, stall is ignored this cycle).
// This prevents a simultaneous wb+stall from leaving a warp stuck.

module warp_table
    import simt_alu_pkg::*;
#(
    parameter int WARPS = simt_alu_pkg::WARPS
)(
    input  logic clk,
    input  logic rst,

    // Stall: mark a warp STALLED (e.g., structural hazard, long-latency op)
    input  logic                  stall_warp,
    input  logic [WARP_ID_W-1:0] stall_warp_id,

    // Unblock: return a warp to READY (e.g., after writeback clears hazard)
    input  logic                  unblock_warp,
    input  logic [WARP_ID_W-1:0] unblock_warp_id,

    // Readiness output
    output logic [WARPS-1:0] warp_ready
);

    warp_state_t warp_state_q [WARPS];

    // Combinational: ready = any warp in READY state
    always_comb begin
        for (int i = 0; i < WARPS; i++) begin
            warp_ready[i] = (warp_state_q[i] == WARP_READY);
        end
    end

    // Sequential: state transitions
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < WARPS; i++) begin
                warp_state_q[i] <= WARP_READY;
            end
        end else begin
            // Unblock takes priority over stall (same cycle)
            if (unblock_warp) begin
                warp_state_q[unblock_warp_id] <= WARP_READY;
            end
            if (stall_warp && !(unblock_warp && (unblock_warp_id == stall_warp_id))) begin
                warp_state_q[stall_warp_id] <= WARP_STALLED;
            end
        end
    end

endmodule
