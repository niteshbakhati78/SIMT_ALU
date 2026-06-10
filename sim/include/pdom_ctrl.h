#pragma once
#include "simt_types.h"
#include <cstdint>
#include <vector>

namespace simt {

// ── PdomInput ──────────────────────────────────────────────────────────────────
// Inputs driven to PdomCtrl each clock cycle (all optional / default-zero).
struct PdomInput {
    bool     branch_fire   = false;  // scheduler issued a conditional branch this cycle
    uint32_t branch_cond   = 0;      // per-lane taken mask (lower cfg.lanes bits)
    uint32_t reconverge_pc = 0;      // PC stored on stack for this divergence level
    bool     path_done     = false;  // current execution path has finished
};

// ── PdomOutput ─────────────────────────────────────────────────────────────────
// Combinational outputs valid at the START of the cycle (before register updates),
// matching the RTL output assignments that read current register values.
struct PdomOutput {
    uint32_t active_mask = 0;     // current thread-execution mask
    bool     stack_empty = true;
    bool     stack_full  = false;
    bool     diverged    = false; // true when deferred paths are waiting on stack
};

// ── PdomCtrl ───────────────────────────────────────────────────────────────────
// Cycle-accurate C++ model of pdom_ctrl.sv.
//
// One PdomCtrl instance per warp.  Each call to tick() models one clock edge:
//   1. Capture outputs from current register state (before any update).
//   2. Compute combinational THEN/ELSE masks from branch_cond & curr_mask.
//   3. Apply sequential (always_ff) state-machine updates:
//        RUN     — handle branch_fire (push ELSE if truly divergent, take THEN),
//                  handle path_done  (pop → POP_WAIT, or reconverge if empty).
//        POP_WAIT — apply registered pop result to curr_mask, return to RUN.
//   4. Return the Step-1 outputs to the caller.
//
// The one-cycle pop latency (registered simt_stack output in the RTL) is modelled
// by saving the popped entry in pop_pending_ during RUN/path_done and consuming it
// one cycle later in POP_WAIT — identical to the RTL's POP_WAIT FSM state.
class PdomCtrl {
public:
    explicit PdomCtrl(const Config& cfg);

    PdomOutput tick(const PdomInput& in);

    // Convenience accessors (read current register state between ticks)
    uint32_t active_mask() const { return curr_mask_; }
    bool     diverged()    const { return sp_ > 0; }

    void reset();

private:
    uint32_t lane_mask() const { return (1u << cfg_.lanes) - 1; }

    enum class State { RUN, POP_WAIT };

    struct StackEntry { uint32_t mask = 0; uint32_t pc = 0; };

    Config                  cfg_;
    uint32_t                curr_mask_;
    State                   state_;
    std::vector<StackEntry> stack_;      // pre-allocated to pdom_depth entries
    int                     sp_;         // number of valid entries  (0 = empty)
    StackEntry              pop_pending_; // registered pop result consumed in POP_WAIT
};

} // namespace simt
