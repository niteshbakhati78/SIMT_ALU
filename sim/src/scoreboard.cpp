#include "scoreboard.h"
#include <algorithm>

namespace simt {

Scoreboard::Scoreboard(const Config& cfg)
    : warps_(cfg.warps), regs_(cfg.regs),
      busy_(cfg.warps * cfg.regs, false) {}

bool Scoreboard::can_issue(int warp_id, int src0, int src1) const {
    return !busy_[idx(warp_id, src0)] && !busy_[idx(warp_id, src1)];
}

void Scoreboard::mark_busy(int warp_id, int reg) {
    busy_[idx(warp_id, reg)] = true;
}

void Scoreboard::clear(int warp_id, int reg) {
    busy_[idx(warp_id, reg)] = false;
}

void Scoreboard::reset() {
    std::fill(busy_.begin(), busy_.end(), false);
}

} // namespace simt
