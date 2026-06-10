#pragma once
#include "simt_types.h"
#include <vector>

namespace simt {

// ── Scoreboard ─────────────────────────────────────────────────────────────────
// Tracks in-flight (busy) destination registers per warp to enforce RAW ordering.
//
// Protocol (mirrors scoreboard.sv):
//   1. Before issuing: call can_issue(warp, src0, src1).
//      Returns false if either source register is busy → stall.
//   2. On issue:       call mark_busy(warp, dst)  if has_dst.
//   3. On writeback:   call clear(warp, dst)       if has_dst.
//
// Writeback clears first; issue marks second — same priority as the RTL.
class Scoreboard {
public:
    explicit Scoreboard(const Config& cfg);

    // Returns true when both sources are free for the given warp.
    bool can_issue(int warp_id, int src0, int src1) const;

    // Mark destination register busy (called at issue time).
    void mark_busy(int warp_id, int reg);

    // Clear destination register (called at writeback time).
    void clear(int warp_id, int reg);

    // Reset all busy bits to zero (mirrors RTL reset).
    void reset();

private:
    int warps_;
    int regs_;
    std::vector<bool> busy_;  // busy_[warp * regs_ + reg]

    int idx(int warp, int reg) const { return warp * regs_ + reg; }
};

} // namespace simt
