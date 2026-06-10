#pragma once
#include "simt_types.h"
#include <optional>
#include <vector>

namespace simt {

// ── ExecPipe ───────────────────────────────────────────────────────────────────
// Fixed-latency execution pipeline modelled as an EXEC_LATENCY-deep shift
// register of optional WbResult entries — a direct C++ analogue of the
// shift-register in exec_pipe.sv.
//
// Protocol each simulation cycle (must follow this order):
//   1. wb = pipe.tick()     — advance pipeline; wb is valid if something exited.
//   2. if issued: pipe.push(entry)  — insert new in-flight instruction.
//
// Timing guarantee (matches RTL):
//   push() at cycle T  →  tick() returns that entry at cycle T + EXEC_LATENCY.
class ExecPipe {
public:
    explicit ExecPipe(const Config& cfg);

    // Advance one cycle: shift all stages left, return the entry that exits
    // from stage 0 (nullopt if nothing was in that slot).
    std::optional<WbResult> tick();

    // Insert a new in-flight entry at the pipeline input (stage DEPTH-1).
    // Must be called after tick() in the same simulation cycle.
    void push(const WbResult& entry);

    void reset();

private:
    int depth_;
    // stages_[0] = oldest (exits first), stages_[depth_-1] = newest (entered last)
    std::vector<std::optional<WbResult>> stages_;
};

} // namespace simt
