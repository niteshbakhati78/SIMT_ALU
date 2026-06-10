// pdom_ctrl.sv — Extension 2: Per-Warp PDOM Reconvergence Stack Controller
//
// Manages thread-mask divergence for one warp using a THEN-first PDOM stack.
//
// On reset: active_mask = all-ones (all threads active, fully converged).
//
// On branch_fire (issued warp had a conditional branch instruction):
//   then_mask = branch_cond & active_mask   (threads taking the branch)
//   else_mask = ~branch_cond & active_mask  (threads not taking it)
//   If BOTH non-zero (TRUE DIVERGENCE):
//     push {else_mask, reconverge_pc} onto the PDOM stack
//     active_mask ← then_mask   (execute THEN path first)
//   If only then or only else: no push, active_mask ← that mask
//
// On path_done (TB signals current path is finished):
//   If stack non-empty: pop → POP_WAIT state → next cycle active_mask = popped mask
//   If stack empty:     active_mask ← all-ones (warp fully reconverged)
//
// diverged = 1 whenever the PDOM stack is non-empty (deferred paths pending).
//
// Pop outputs from simt_stack are registered (one-cycle latency), so we use
// the same RUN/POP_WAIT FSM pattern as simt_branch_control.

module pdom_ctrl
    import simt_alu_pkg::*;
#(
    parameter int LANES = simt_alu_pkg::LANES,
    parameter int PC_W  = simt_alu_pkg::PC_W,
    parameter int DEPTH = simt_alu_pkg::PDOM_DEPTH
)(
    input  logic clk,
    input  logic rst,

    // Branch event — fires when the scheduler issues a branch instr for this warp
    input  logic             branch_fire,
    input  logic [LANES-1:0] branch_cond,    // per-lane condition (1=taken, 0=not-taken)
    input  logic [PC_W-1:0]  reconverge_pc,  // stored on stack for this divergence level

    // Path completion — TB asserts when the current path has finished executing
    input  logic             path_done,

    // Current active thread mask → drives ALU lane_mask for this warp
    output logic [LANES-1:0] active_mask,

    // Status
    output logic             stack_empty,
    output logic             stack_full,
    output logic             diverged        // deferred paths are waiting
);

    // -----------------------------------------------------------------------
    // Internal current execution mask
    // -----------------------------------------------------------------------
    logic [LANES-1:0] curr_mask;

    // Combinational THEN/ELSE splits from the current mask
    logic [LANES-1:0] then_mask, else_mask;
    always_comb begin
        then_mask = branch_cond & curr_mask;
        else_mask = ~branch_cond & curr_mask;
    end

    // -----------------------------------------------------------------------
    // PDOM Stack instance (reuse simt_stack)
    // -----------------------------------------------------------------------
    logic             st_push, st_pop;
    logic [LANES-1:0] st_push_mask;
    logic [PC_W-1:0]  st_push_pc;
    logic [LANES-1:0] st_pop_mask;
    logic [PC_W-1:0]  st_pop_pc;
    logic [$clog2(DEPTH+1)-1:0] st_count;

    simt_stack #(
        .LANES(LANES),
        .PC_W (PC_W),
        .DEPTH(DEPTH)
    ) u_stack (
        .clk      (clk),
        .rst      (rst),
        .push     (st_push),
        .push_mask(st_push_mask),
        .push_pc  (st_push_pc),
        .pop      (st_pop),
        .pop_mask (st_pop_mask),
        .pop_pc   (st_pop_pc),
        .empty    (stack_empty),
        .full     (stack_full),
        .count    (st_count)
    );

    // -----------------------------------------------------------------------
    // FSM: RUN normal execution, POP_WAIT consumes registered pop outputs
    // -----------------------------------------------------------------------
    typedef enum logic [0:0] { RUN, POP_WAIT } state_t;
    state_t state;

    // Combinational: stack control pulses
    always_comb begin
        st_push      = 1'b0;
        st_pop       = 1'b0;
        st_push_mask = '0;
        st_push_pc   = '0;

        if (state == RUN) begin
            // Push ELSE path if TRUE divergence (both masks non-zero)
            if (branch_fire && (then_mask != '0) && (else_mask != '0) && !stack_full) begin
                st_push      = 1'b1;
                st_push_mask = else_mask;
                st_push_pc   = reconverge_pc;
            end
            // Pop deferred path when current path is done
            if (path_done && !stack_empty) begin
                st_pop = 1'b1;
            end
        end
    end

    // Sequential: mask and state transitions
    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= RUN;
            curr_mask <= '1;  // fully converged on reset
        end else begin
            case (state)
                RUN: begin
                    // Process branch result
                    if (branch_fire) begin
                        if (then_mask != '0 && else_mask == '0)
                            curr_mask <= then_mask;
                        else if (then_mask == '0 && else_mask != '0)
                            curr_mask <= else_mask;
                        else if (then_mask != '0 && else_mask != '0)
                            curr_mask <= then_mask;  // THEN-first: execute taken path
                        // else: no active threads — leave mask unchanged
                    end

                    // Process path completion
                    if (path_done) begin
                        if (!stack_empty) begin
                            state <= POP_WAIT;   // wait one cycle for stack pop output
                        end else begin
                            curr_mask <= '1;     // all paths done — full reconvergence
                        end
                    end
                end

                POP_WAIT: begin
                    // Stack pop output is now registered and valid
                    curr_mask <= st_pop_mask;
                    state     <= RUN;
                end
            endcase
        end
    end

    // Outputs
    assign active_mask = curr_mask;
    assign diverged    = !stack_empty;  // deferred paths waiting on stack

endmodule
