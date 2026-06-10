#pragma once
#include "simt_types.h"
#include "scoreboard.h"
#include "warp_table.h"
#include "warp_scheduler.h"
#include "exec_pipe.h"
#include <optional>
#include <vector>

namespace simt {

// ── MiniSM ─────────────────────────────────────────────────────────────────────
// Top-level integration of the five sub-components, matching mini_sm_top.sv.
//
// Each call to tick() models one clock cycle:
//   1. Snapshot eligibility (can_issue uses the scoreboard state from last cycle).
//   2. Scheduler selects a warp (round-robin among eligible warps).
//   3. Pipeline advances: exec_pipe.tick() → writeback result.
//   4. Scoreboard updated: clear wb-dst first, then mark issued-dst (same cycle
//      semantics as the RTL always_ff where wb-clear has priority over issue-set).
//   5. Stall counters classified and cycle counter incremented.
//
// Caller interface:
//   - Provide warp_instrs[w] = InstrMeta for each warp that has a pending
//     instruction, or nullopt if that warp slot is idle this cycle.
//   - Same InstrMeta can be supplied every cycle until the caller changes it.
class MiniSM {
public:
    explicit MiniSM(const Config& cfg);

    struct TickOutput {
        std::optional<int>      issued_warp;  // warp that issued this cycle
        std::optional<WbResult> writeback;    // writeback that completed this cycle
    };

    // Drive one simulation cycle and return what happened.
    TickOutput tick(const std::vector<std::optional<InstrMeta>>& warp_instrs);

    const PerfCounters& stats() const { return counters_; }

    // Hard reset: clears all sub-components and counters.
    void reset();

private:
    Config        cfg_;
    Scoreboard    scoreboard_;
    WarpTable     warp_table_;
    WarpScheduler scheduler_;
    ExecPipe      exec_pipe_;
    PerfCounters  counters_;
};

} // namespace simt
