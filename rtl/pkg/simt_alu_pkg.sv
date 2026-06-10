// simt_alu_pkg.sv — Phase 4 Mini-SM + Extensions shared package
// Include guard: prevents duplicate package definition when multiple RTL
// files are compiled in a single vlog invocation.
`ifndef SIMT_ALU_PKG_SV
`define SIMT_ALU_PKG_SV

package simt_alu_pkg;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int LANES        = 8;   // SIMT lanes per warp
    parameter int DATA_WIDTH   = 32;  // Per-lane data width
    parameter int WARPS        = 4;   // Number of warps
    parameter int REGS         = 16;  // Architectural registers per warp
    parameter int EXEC_LATENCY = 4;   // Fixed execution pipeline depth (cycles)
    parameter int PC_W         = 16;  // Program counter width (Extension 2)
    parameter int PDOM_DEPTH   = 8;   // PDOM stack depth per warp (Extension 2)

    // Derived widths (constants at elaboration time)
    localparam int WARP_ID_W = $clog2(WARPS);  // 2 bits for 4 warps
    localparam int REG_ID_W  = $clog2(REGS);   // 4 bits for 16 regs

    // -------------------------------------------------------------------------
    // Warp state enum
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        WARP_READY   = 2'd0,
        WARP_STALLED = 2'd1
    } warp_state_t;

    // -------------------------------------------------------------------------
    // Instruction metadata struct (packed so exec_pipe can shift it)
    // Total: WARP_ID_W + REG_ID_W*3 + 1 + 3 + LANES = 2+12+1+3+8 = 26 bits
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic [WARP_ID_W-1:0] warp_id;   // Which warp issued this
        logic [REG_ID_W-1:0]  src0;      // Source register 0
        logic [REG_ID_W-1:0]  src1;      // Source register 1
        logic [REG_ID_W-1:0]  dst;       // Destination register
        logic                  has_dst;   // 1 if instruction writes a register
        logic [2:0]            sel;       // ALU op select
        logic [LANES-1:0]      lane_mask; // Initial/override lane mask (PDOM takes priority)
    } instr_meta_t;

    // -------------------------------------------------------------------------
    // Extension 2: PDOM stack entry
    // Stores a deferred execution path for reconvergence
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic [PC_W-1:0]   reconv_pc;  // Post-dominator reconvergence PC
        logic [LANES-1:0]  mask;       // Thread active mask for this deferred path
    } pdom_entry_t;

endpackage

`endif // SIMT_ALU_PKG_SV
