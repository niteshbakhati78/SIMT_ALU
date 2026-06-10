// simt_stack.sv (Phase 3)
// PURPOSE
//   GPUs executing SIMT must handle branch divergence. When a warp splits into
//   THEN and ELSE lanes, hardware executes one path now and must "remember" the
//   other path to run later. This module provides that memory as a small stack.
//
// WHAT IS STORED PER ENTRY
//   - saved_mask : which lanes are deferred (e.g., ELSE lanes)
//   - saved_pc   : where that deferred path should resume (often reconverge PC)
//
// INTERFACE SUMMARY
//   - push=1 : store (push_mask, push_pc) if not full
//   - pop=1  : output top entry (pop_mask, pop_pc) and remove it if not empty
//
// DESIGN CHOICE (IMPORTANT)
//   Pop outputs are REGISTERED (update on the clock edge of a pop).
//   This is easy to time/verify and realistic for control logic.
//   => Any consumer should treat pop data as valid AFTER the pop edge.
// Notes:
//  - pop outputs are registered (change on posedge when pop asserted)
//  - push and pop same cycle: pop happens first, then push to the new top

module simt_stack #(
    parameter int LANES = 8,
    parameter int PC_W = 16,
    parameter int DEPTH = 8
) (
    input  logic clk,
    input  logic rst,

    // Push interface
    input  logic push,
    input  logic [LANES-1:0] push_mask,
    input  logic [PC_W-1:0]  push_pc,

    // Pop interface
    input  logic pop,
    output logic [LANES-1:0] pop_mask,
    output logic [PC_W-1:0]  pop_pc,

    // Status
    output logic empty,
    output logic full,
    output logic [$clog2(DEPTH+1)-1:0] count
);

    //  Memory
    // Storage arrays: entry i holds mask_mem[i] and pc_mem[i]
    logic [LANES-1:0] mask_mem [0:DEPTH-1];
    logic [PC_W-1:0]  pc_mem [0:DEPTH-1];

    // Stack pointer sp = number of valid entries (0..DEPTH)
    //   empty when sp==0
    //   top entry index is (sp-1)
    //   next push writes at index sp
    //logic [$clog2(DEPTH+1)-1:0] sp;

    // Status is purely combinational from sp
    always_comb begin
        empty = (count == '0);
        //full = (count == DEPTH[$clog2(DEPTH+1)-1:0]);
        full = (count == DEPTH[$bits(count)-1:0]);
        //count = sp;
    end

    // Stack operation
    // Sequential behavior:
    //   - POP happens first (if requested and not empty)
    //   - PUSH happens second (if requested and not full)
    // If push and pop happen in the same cycle, the net stack depth is unchanged
    // and the push overwrites the popped slot (standard stack behavior).
    always_ff @( posedge clk ) begin 
        if (rst) begin
            //sp <= '0;
            count <= '0;
            pop_mask <= '0;
            pop_pc <= '0;

            // Optional: clear memory (not required for correctness)
            for (int i = 0; i < DEPTH; i++) begin
                mask_mem[i] <= '0;
                pc_mem[i]   <= '0;
            end
        end
        else begin
            // Default: hold outputs unless we pop
            // (pop_mask/pop_pc keep last popped entry)

            // Case handling:
            // - If both push and pop are asserted in same cycle:
            //     We pop the current top, then push the new entry.
            //     Net count remains unchanged (if neither empty/full blocks).
            //
            // This behavior is sensible and avoids weird corner cases.
            //
            // Your Phase 3A TB does NOT push and pop in same cycle,
            // but this makes the block robust for later phases.
            

            logic do_pop;
            logic do_push;

            do_pop = pop && (count != '0);
            do_push = push && (count != DEPTH[$bits(count)-1:0]);

            // POP first (if valid)
            if (do_pop) begin
                // Remove top entry: decrement sp and return entry at (sp-1)
                //sp <= sp - 1;
                pop_mask <= mask_mem[count - 1];
                pop_pc <= pc_mem[count - 1];
            end

            // Update count and memory depending on push/pop combination
            unique case ({do_push, do_pop})
                2'b10: begin
                    // push only
                    mask_mem[count] <= push_mask;
                    pc_mem[count]   <= push_pc;
                    count           <= count + 1;
                end

                2'b01: begin
                    // pop only
                    count <= count - 1;
                end 
                
                2'b11: begin
                    // pop + push in same cycle (count unchanged)
                    // pop reads old top (count-1)
                    // push writes into the "new top" position after pop,
                    // which is index (count-1).
                    mask_mem[count - 1] <= push_mask;
                    pc_mem[count - 1]   <= push_pc;
                    // count unchanged
                end
                default: begin
                    // neither
                    count <= count;
                end
            endcase
        end
    end
    
endmodule