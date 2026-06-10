// warp_scheduler.sv — Phase 4 Mini-SM
// Round-robin warp scheduler.
//
// Each cycle, starting from rr_ptr_q, scans warps in order and picks
// the first warp where warp_ready && warp_can_issue && warp_has_instr.
// On issue, rr_ptr advances to (issue_warp_id + 1) mod WARPS so the
// next selected warp rotates fairly.

module warp_scheduler
    import simt_alu_pkg::*;
#(
    parameter int WARPS = simt_alu_pkg::WARPS
)(
    input  logic clk,
    input  logic rst,

    // Eligibility inputs (all WARPS-wide)
    input  logic [WARPS-1:0] warp_ready,      // from warp_table
    input  logic [WARPS-1:0] warp_can_issue,  // from scoreboard (no RAW hazard)
    input  logic [WARPS-1:0] warp_has_instr,  // from TB: warp has a pending instruction

    // Issue outputs
    output logic                      issue_valid,
    output logic [WARP_ID_W-1:0]     issue_warp_id
);

    logic [WARP_ID_W-1:0] rr_ptr_q;

    // -----------------------------------------------------------------------
    // Combinational: find first eligible warp starting from rr_ptr_q
    // -----------------------------------------------------------------------
    always_comb begin
        issue_valid   = 1'b0;
        issue_warp_id = '0;
        for (int i = 0; i < WARPS; i++) begin
            automatic int idx = (rr_ptr_q + i) % WARPS;
            if (!issue_valid
                && warp_ready[idx]
                && warp_can_issue[idx]
                && warp_has_instr[idx])
            begin
                issue_valid   = 1'b1;
                issue_warp_id = WARP_ID_W'(idx);
            end
        end
    end

    // -----------------------------------------------------------------------
    // Sequential: advance rr_ptr on every issue
    // -----------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            rr_ptr_q <= '0;
        end else if (issue_valid) begin
            // Wrap around: if last warp issued, next ptr = 0
            rr_ptr_q <= (issue_warp_id == WARP_ID_W'(WARPS-1))
                        ? '0
                        : issue_warp_id + 1'b1;
        end
    end

endmodule
