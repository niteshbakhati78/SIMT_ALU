#pragma once
#include "simt_types.h"
#include <vector>

namespace simt {

// ── WarpTable ──────────────────────────────────────────────────────────────────
// Per-warp state machine: READY or STALLED.
// All warps start READY on construction and after reset().
//
// The MiniSM top drives transitions:
//   - set_stalled() when the scoreboard blocks an issue.
//   - set_ready()   when a writeback clears the blocking register
//     (or when there was no dependency and the warp can issue next cycle).
//
// In this model the warp table is consulted by the scheduler; it does NOT
// automatically re-ready a warp — that responsibility belongs to MiniSM,
// matching the RTL's always_ff logic in wrap_table.sv.
class WarpTable {
public:
    explicit WarpTable(const Config& cfg);

    void set_ready(int warp_id);
    void set_stalled(int warp_id);
    bool is_ready(int warp_id) const;

    // Reset all warps to READY.
    void reset();

private:
    int warps_;
    std::vector<WarpState> state_;
};

} // namespace simt
