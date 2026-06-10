#include "warp_scheduler.h"

namespace simt {

WarpScheduler::WarpScheduler(const Config& cfg)
    : warps_(cfg.warps), rr_ptr_(0) {}

std::optional<int> WarpScheduler::select(
    const std::vector<bool>& has_instr,
    const std::vector<bool>& ready,
    const std::vector<bool>& can_issue) const
{
    for (int i = 0; i < warps_; i++) {
        int w = (rr_ptr_ + i) % warps_;
        if (has_instr[w] && ready[w] && can_issue[w])
            return w;
    }
    return std::nullopt;
}

void WarpScheduler::advance(int issued_warp) {
    rr_ptr_ = (issued_warp + 1) % warps_;
}

void WarpScheduler::reset() {
    rr_ptr_ = 0;
}

} // namespace simt
