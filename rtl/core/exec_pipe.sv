// exec_pipe.sv — Phase 4 Mini-SM
// Fixed-latency execution pipeline.
//
// On issue_fire: load stage 0 with instruction metadata + valid=1.
// Each cycle: shift all stages forward by one.
// At stage EXEC_LATENCY-1: emit wb_valid + writeback metadata.
//
// The pipeline always accepts a new instruction every cycle (no backpressure).
// Metadata shifts in lockstep with the valid bit.

module exec_pipe
    import simt_alu_pkg::*;
#(
    parameter int WARPS        = simt_alu_pkg::WARPS,
    parameter int REGS         = simt_alu_pkg::REGS,
    parameter int EXEC_LATENCY = simt_alu_pkg::EXEC_LATENCY
)(
    input  logic clk,
    input  logic rst,

    // Issue inputs
    input  logic                  issue_fire,
    input  logic [WARP_ID_W-1:0] issue_warp_id,
    input  logic [REG_ID_W-1:0]  issue_dst,
    input  logic                  issue_has_dst,

    // Writeback outputs (appear EXEC_LATENCY cycles after issue)
    output logic                  wb_valid,
    output logic [WARP_ID_W-1:0] wb_warp_id,
    output logic [REG_ID_W-1:0]  wb_dst,
    output logic                  wb_has_dst
);

    // Pipeline shift registers
    logic                  valid_pipe   [EXEC_LATENCY];
    logic [WARP_ID_W-1:0] warp_id_pipe [EXEC_LATENCY];
    logic [REG_ID_W-1:0]  dst_pipe     [EXEC_LATENCY];
    logic                  has_dst_pipe [EXEC_LATENCY];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < EXEC_LATENCY; i++) begin
                valid_pipe[i]   <= 1'b0;
                warp_id_pipe[i] <= '0;
                dst_pipe[i]     <= '0;
                has_dst_pipe[i] <= 1'b0;
            end
        end else begin
            // Stage 0: load from issue
            valid_pipe[0]   <= issue_fire;
            warp_id_pipe[0] <= issue_warp_id;
            dst_pipe[0]     <= issue_dst;
            has_dst_pipe[0] <= issue_has_dst;
            // Stages 1..EXEC_LATENCY-1: shift forward
            for (int i = 1; i < EXEC_LATENCY; i++) begin
                valid_pipe[i]   <= valid_pipe[i-1];
                warp_id_pipe[i] <= warp_id_pipe[i-1];
                dst_pipe[i]     <= dst_pipe[i-1];
                has_dst_pipe[i] <= has_dst_pipe[i-1];
            end
        end
    end

    // Writeback = tail of the pipeline
    assign wb_valid   = valid_pipe[EXEC_LATENCY-1];
    assign wb_warp_id = warp_id_pipe[EXEC_LATENCY-1];
    assign wb_dst     = dst_pipe[EXEC_LATENCY-1];
    assign wb_has_dst = has_dst_pipe[EXEC_LATENCY-1];

endmodule
