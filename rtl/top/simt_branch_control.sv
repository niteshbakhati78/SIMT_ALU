// simt_branch_control.sv (Phase 3B)
// Divergence + reconvergence controller using simt_stack.
// PURPOSE
// Implement the SIMT "CONTROL-FLOW MASK MACHINE" used by GPUs
// 1) Abranch produces per-lane condition bits (cond[]).
// 2) The wrap mask splits into two masks:
//      then_mask = mask_in & cond
//      else_mask = mask_in & ~cond
// 3) If both are non-zero, the wrap diverges:
//    - Execute one path now (THEN-first policy)
//    - Push the other path onto a SIMT stack to execute later
// 4) When the current path completes, pop from the stack and continue.
// IMPORTANT IMPLEMENTATION DETAIL
//   simt_stack returns popped values as REGISTERED outputs (pop_mask/pop_pc).
//   Therefore, the controller must:
//     - assert pop in one cycle
//     - consume pop_mask/pop_pc in the NEXT cycle
//   We implement this with a tiny FSM: RUN and POP_WAIT.
// Policy: THEN-first
// - On branch_valid:
//     then_mask = mask_in & cond
//     else_mask = mask_in & ~cond
//   If both non-zero (divergence):
//     push (else_mask, pc_in+1) 
//     next = (then_mask, pc_in+1) // placeholder next PC
//   If only one non-zero:
//     next = that mask (no push) 
// - On path_done:
//     if stack not empty: pop and resume popped context
//     else: curr_mask becomes 0 (wrap finished)
//
// Notes:
// - This module holds the "current context" in registers: curr_mask/curr_pc.
// - Stack push/pop are asserted for exactly 1 cycle.


module simt_branch_control #(
    parameter int LANES = 8,
    parameter int PC_W = 16,
    parameter int STACK_DEPTH = 8
) (
    input  logic clk,
    input  logic rst,

    // Current context in (for branch event)
    input  logic [LANES-1:0] mask_in,
    input  logic [PC_W-1:0]  pc_in,

    // Branch event
    input  logic branch_valid,
    input  logic [LANES-1:0] cond,
    input  logic [PC_W-1:0] reconverge_pc,

    // Indicates the currently executing path has finished
    input  logic path_done,

    // Current context out (what to execute now)
    output logic [LANES-1:0] mask_out,
    output logic [PC_W-1:0]  pc_out,

    // Stack status
    output logic stack_empty,
    output logic stack_full
);

    // Split masks
    logic [LANES-1:0] then_mask, else_mask;
    always_comb begin
        then_mask = mask_in & cond;
        else_mask = mask_in & ~cond;
    end

    // Stack Signals
    logic  st_push, st_pop;
    logic  [LANES-1:0] st_push_mask;
    logic  [PC_W-1:0]  st_push_pc;
    logic  [LANES-1:0] st_pop_mask;
    logic  [PC_W-1:0]  st_pop_pc;
    logic [$clog2(STACK_DEPTH+1)-1:0] st_count;

    simt_stack #(
        .LANES(LANES),
        .PC_W(PC_W),
        .DEPTH(STACK_DEPTH)
    ) U_STACK (
        .clk(clk),
        .rst(rst),
        .push(st_push),
        .push_mask(st_push_mask),
        .push_pc(st_push_pc),
        .pop(st_pop),
        .pop_mask(st_pop_mask),
        .pop_pc(st_pop_pc),
        .empty(stack_empty),
        .full(stack_full),
        .count(st_count)
    );

    // Current execution context registers
    // These represent "what the warp is executing right now".
    logic [LANES-1:0] curr_mask;
    logic [PC_W-1:0]  curr_pc;

    // Small FSM to handle stack pop timing (registered pop outputs)
    typedef enum logic [0:0] {
        RUN,
        POP_WAIT
    } state_t;

    // Default stack control (combinational pulses)
    always_comb begin 
        st_push      = 1'b0;
        st_pop       = 1'b0;
        st_push_mask = '0;
        st_push_pc   = '0;

        // Push deferred ELSE path only on real divergence
        if (state == RUN &&
            branch_valid &&
            (then_mask != '0) &&
            (else_mask != '0) &&
            !stack_full) begin
            st_push      = 1'b1;
            st_push_mask = else_mask;
            st_push_pc   = reconverge_pc;
        end

        // Pop requested when current path is done and stack has more work
        // Pop is asserted in RUN; results are consumed in POP_WAIT next cycle.
        if (state == RUN && path_done && !stack_empty) begin
            st_pop = 1'b1;
        end
    end 

    
    // Sequential state/context updates
    always_ff @( posedge clk ) begin
        if (rst) begin
            state <= RUN;
            curr_mask <= '0;
            curr_pc <= '0;
        end
        else begin
            case (state)
                // RUN: normal operation
                RUN: begin
                    // 1) Handle branch decisions (THEN-first policy)
                    if (branch_valid) begin
                        if ((then_mask != '0) && (else_mask == '0)) begin
                            // No divergence: only THEN has active lanes
                            curr_mask <= then_mask;
                            curr_pc   <= pc_in + 1;
                        end else if ((then_mask == '0) && (else_mask != '0)) begin
                            // No divergence: only ELSE has active lanes
                            curr_mask <= else_mask;
                            curr_pc   <= pc_in + 1;
                        end else if ((then_mask != '0) && (else_mask != '0)) begin
                            // Divergence: execute THEN now; ELSE is pushed via st_push
                            curr_mask <= then_mask;
                            curr_pc   <= pc_in + 1;
                        end else begin
                            // mask_in had no active lanes
                            curr_mask <= '0;
                        end
                    end

                    // 2) Handle path completion
                    // If stack has more work, we pop this cycle and go to POP_WAIT
                    if (path_done) begin
                        if (!stack_empty) begin
                            state <= POP_WAIT; // consume st_pop_* next cycle
                        end else begin
                            // No deferred paths: warp is finished
                            curr_mask <= '0;
                        end
                    end
                end
                // POP_WAIT: st_pop_mask/st_pop_pc are now valid (registered)
                POP_WAIT: begin
                    curr_mask <= st_pop_mask;
                    curr_pc   <= st_pop_pc;
                    state     <= RUN;
                end

            endcase
        end
    end
    // Output the currently selected execution context
    always_comb begin
        mask_out = curr_mask;
        pc_out = curr_pc;
    end       
endmodule