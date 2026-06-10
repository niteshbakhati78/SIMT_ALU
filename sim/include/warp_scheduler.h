#pragma once
#include "simt_types.h"
#include <optional>
#include <vector>

namespace simt {

// ── WarpScheduler ──────────────────────────────────────────────────────────────
// Round-robin arbiter across WARPS warps.
//
// Each call to select() scans from rr_ptr_ forward, returning the first warp
// where all three eligibility conditions hold simultaneously:
//   has_instr  — caller has a pending instruction for this warp
//   ready      — warp_table reports READY
//   can_issue  — scoreboard reports no RAW hazard on src0/src1
//
// On a successful issue the caller must call advance(issued_warp) so the
// pointer advances past the issued warp for the next cycle, matching the
// always_ff rr_ptr update in warp_scheduler.sv.
class WarpScheduler {
public:
    explicit WarpScheduler(const Config& cfg);

    // Returns the winning warp_id or nullopt when no warp is eligible.
    std::optional<int> select(const std::vector<bool>& has_instr,
                              const std::vector<bool>& ready,
                              const std::vector<bool>& can_issue) const;

    // Advance rr_ptr to (issued_warp + 1) % WARPS after a successful issue.
    void advance(int issued_warp);

    void reset();  // rr_ptr_ → 0

private:
    int warps_;
    int rr_ptr_;
};

} // namespace simt
