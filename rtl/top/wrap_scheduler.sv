// wrap_scheduler.sv — Phase 4
// Thin wrapper around rtl/control/warp_scheduler.sv.
// Allows mini_sm_top to instantiate this wrapper for cleaner hierarchy,
// or can be bypassed by instantiating warp_scheduler directly.

module wrap_scheduler
    import simt_alu_pkg::*;
#(
    parameter int WARPS = simt_alu_pkg::WARPS
)(
    input  logic clk,
    input  logic rst,

    input  logic [WARPS-1:0] warp_ready,
    input  logic [WARPS-1:0] warp_can_issue,
    input  logic [WARPS-1:0] warp_has_instr,

    output logic                  issue_valid,
    output logic [WARP_ID_W-1:0] issue_warp_id
);

    warp_scheduler #(.WARPS(WARPS)) u_sched (
        .clk           (clk),
        .rst           (rst),
        .warp_ready    (warp_ready),
        .warp_can_issue(warp_can_issue),
        .warp_has_instr(warp_has_instr),
        .issue_valid   (issue_valid),
        .issue_warp_id (issue_warp_id)
    );

endmodule
