#include "exec_pipe.h"
#include <algorithm>

namespace simt {

ExecPipe::ExecPipe(const Config& cfg)
    : depth_(cfg.exec_latency),
      stages_(cfg.exec_latency, std::nullopt) {}

std::optional<WbResult> ExecPipe::tick() {
    // Capture what exits from the oldest stage
    std::optional<WbResult> wb = stages_[0];
    // Shift all stages toward the output (index 0)
    for (int i = 0; i < depth_ - 1; i++)
        stages_[i] = stages_[i + 1];
    // Clear the newest stage so push() can fill it this cycle
    stages_[depth_ - 1] = std::nullopt;
    return wb;
}

void ExecPipe::push(const WbResult& entry) {
    stages_[depth_ - 1] = entry;
}

void ExecPipe::reset() {
    std::fill(stages_.begin(), stages_.end(), std::nullopt);
}

} // namespace simt
