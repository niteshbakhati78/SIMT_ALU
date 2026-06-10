#include "pdom_ctrl.h"

namespace simt {

PdomCtrl::PdomCtrl(const Config& cfg)
    : cfg_(cfg),
      curr_mask_((1u << cfg.lanes) - 1),  // all lanes active on reset
      state_(State::RUN),
      stack_(cfg.pdom_depth),
      sp_(0),
      pop_pending_{} {}

PdomOutput PdomCtrl::tick(const PdomInput& in)
{
    const uint32_t lm = lane_mask();

    // ── Step 1: outputs from current state (before this cycle's register updates)
    PdomOutput out;
    out.active_mask = curr_mask_;
    out.stack_empty = (sp_ == 0);
    out.stack_full  = (sp_ >= cfg_.pdom_depth);
    out.diverged    = (sp_ > 0);

    // ── Step 2: combinational THEN / ELSE mask split ──────────────────────────
    const uint32_t then_mask = in.branch_cond  & curr_mask_ & lm;
    const uint32_t else_mask = (~in.branch_cond) & curr_mask_ & lm;

    // ── Step 3: sequential (always_ff) state-machine update ──────────────────
    switch (state_) {
        case State::RUN:
            // Process branch result — mirrors the RTL always_ff RUN branch
            if (in.branch_fire) {
                if (then_mask != 0 && else_mask == 0) {
                    curr_mask_ = then_mask;                // uniform taken
                } else if (then_mask == 0 && else_mask != 0) {
                    curr_mask_ = else_mask;                // uniform not-taken
                } else if (then_mask != 0 && else_mask != 0) {
                    // True divergence: push ELSE path, execute THEN first
                    if (sp_ < cfg_.pdom_depth)
                        stack_[sp_++] = {else_mask, in.reconverge_pc};
                    curr_mask_ = then_mask;
                }
                // both zero: no active threads — leave curr_mask unchanged
            }

            // Process path completion
            if (in.path_done) {
                if (sp_ > 0) {
                    // Pop top entry; result becomes visible next cycle (POP_WAIT)
                    pop_pending_ = stack_[--sp_];
                    state_ = State::POP_WAIT;
                } else {
                    curr_mask_ = lm;      // stack empty → full reconvergence
                }
            }
            break;

        case State::POP_WAIT:
            // Registered pop output is now valid — apply to curr_mask
            curr_mask_ = pop_pending_.mask;
            state_     = State::RUN;
            break;
    }

    return out;
}

void PdomCtrl::reset()
{
    curr_mask_   = lane_mask();
    state_       = State::RUN;
    sp_          = 0;
    pop_pending_ = {};
}

} // namespace simt
