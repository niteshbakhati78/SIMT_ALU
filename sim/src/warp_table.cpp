#include "warp_table.h"
#include <algorithm>

namespace simt {

WarpTable::WarpTable(const Config& cfg)
    : warps_(cfg.warps), state_(cfg.warps, WarpState::READY) {}

void WarpTable::set_ready(int warp_id) {
    state_[warp_id] = WarpState::READY;
}

void WarpTable::set_stalled(int warp_id) {
    state_[warp_id] = WarpState::STALLED;
}

bool WarpTable::is_ready(int warp_id) const {
    return state_[warp_id] == WarpState::READY;
}

void WarpTable::reset() {
    std::fill(state_.begin(), state_.end(), WarpState::READY);
}

} // namespace simt
