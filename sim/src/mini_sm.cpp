#include "mini_sm.h"

namespace simt {

MiniSM::MiniSM(const Config& cfg)
    : cfg_(cfg),
      scoreboard_(cfg),
      warp_table_(cfg),
      scheduler_(cfg),
      exec_pipe_(cfg),
      counters_{} {}

MiniSM::TickOutput MiniSM::tick(
    const std::vector<std::optional<InstrMeta>>& warp_instrs)
{
    TickOutput out;
    const int W = cfg_.warps;

    // ── Step 1: snapshot eligibility from CURRENT state ───────────────────────
    // This mirrors the combinational signals in the RTL that are evaluated
    // before the posedge captures any register updates for this cycle.
    std::vector<bool> has_instr(W), ready(W), can_issue_vec(W);
    for (int w = 0; w < W; w++) {
        has_instr[w] = warp_instrs[w].has_value();
        ready[w]     = warp_table_.is_ready(w);
        if (has_instr[w]) {
            const InstrMeta& m = *warp_instrs[w];
            can_issue_vec[w] = scoreboard_.can_issue(w, m.src0, m.src1);
        }
    }

    // ── Step 2: scheduler selects ──────────────────────────────────────────────
    auto issued_warp = scheduler_.select(has_instr, ready, can_issue_vec);
    out.issued_warp  = issued_warp;

    // ── Step 3: advance execution pipeline → get writeback ────────────────────
    auto wb    = exec_pipe_.tick();
    out.writeback = wb;

    // ── Step 4: apply register updates (wb clears first, issue marks second) ───
    // Matches the RTL always_ff priority where writeback clear takes precedence
    // over a same-cycle issue mark on the same register.
    if (wb && wb->has_dst)
        scoreboard_.clear(wb->warp_id, wb->dst);

    if (issued_warp) {
        const InstrMeta& m = *warp_instrs[*issued_warp];
        if (m.has_dst)
            scoreboard_.mark_busy(*issued_warp, m.dst);
        exec_pipe_.push(WbResult{*issued_warp, m.dst, m.has_dst});
        scheduler_.advance(*issued_warp);
    }

    // ── Step 5: stall classification and counter updates ──────────────────────
    if (issued_warp) {
        counters_.instructions++;
        counters_.cycles_issuing++;
    } else {
        bool any_data_stall = false;
        bool any_work       = false;
        for (int w = 0; w < W; w++) {
            if (has_instr[w] && ready[w]) {
                any_work = true;
                if (!can_issue_vec[w]) any_data_stall = true;
            }
        }
        if (any_data_stall)   counters_.stall_data++;
        else if (!any_work)   counters_.stall_no_warp++;
    }

    if (wb) counters_.wb_count++;
    counters_.cycles++;

    return out;
}

void MiniSM::reset() {
    scoreboard_.reset();
    warp_table_.reset();
    scheduler_.reset();
    exec_pipe_.reset();
    counters_ = {};
}

} // namespace simt
