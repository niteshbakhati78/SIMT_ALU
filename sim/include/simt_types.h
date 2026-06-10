#pragma once
#include <cstdint>
#include <string>

namespace simt {

// ── Hardware configuration ─────────────────────────────────────────────────────
// All parameters are runtime values so the same binary can sweep configurations.
struct Config {
    int warps        = 4;
    int regs         = 16;
    int lanes        = 8;
    int data_width   = 32;
    int exec_latency = 4;
    int pc_width     = 16;
    int pdom_depth   = 8;
};

// ── Warp state ─────────────────────────────────────────────────────────────────
enum class WarpState { READY, STALLED };

// ── Instruction metadata ───────────────────────────────────────────────────────
struct InstrMeta {
    int  warp_id   = 0;
    int  src0      = 0;   // source register 0
    int  src1      = 0;   // source register 1
    int  dst       = 0;   // destination register
    bool has_dst   = false;
    int  sel       = 0;   // ALU op select (0=ADD, 1=SUB, …)
    bool is_branch = false;
};

// ── Writeback result emitted by the execution pipeline ─────────────────────────
struct WbResult {
    int  warp_id = 0;
    int  dst     = 0;
    bool has_dst = false;
};

// ── Branch info passed to the PDOM controller ─────────────────────────────────
struct BranchInfo {
    uint32_t cond_mask     = 0;  // per-lane taken mask
    uint32_t reconverge_pc = 0;
};

// ── Performance counters ───────────────────────────────────────────────────────
struct PerfCounters {
    uint64_t cycles               = 0;
    uint64_t instructions         = 0;
    uint64_t stall_data           = 0;  // RAW hazard stalls
    uint64_t stall_structural     = 0;
    uint64_t stall_memory         = 0;
    uint64_t stall_no_warp        = 0;  // no eligible warp this cycle
    uint64_t cycles_issuing       = 0;  // cycles where an issue fired
    uint64_t wb_count             = 0;
    uint64_t diverge_events       = 0;
    uint64_t masked_thread_cycles = 0;

    double ipc() const {
        return cycles > 0 ? static_cast<double>(instructions) / cycles : 0.0;
    }
    double warp_efficiency() const {
        return cycles > 0 ? 100.0 * static_cast<double>(cycles_issuing) / cycles : 0.0;
    }

    // Write in the same key=value format consumed by perf_sweep.py
    void write_file(const std::string& path) const;
};

} // namespace simt
