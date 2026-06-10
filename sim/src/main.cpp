// main.cpp — Mini-SM C++ simulation CLI
//
// Runs a RAW-heavy workload: every warp continuously presents the instruction
//   r0 + r1 → r0   (src0=r0 reads previous write, dst=r0 creates next RAW)
// This maximises data-hazard stalls and demonstrates multi-warp latency hiding.
//
// Steady-state IPC theory:
//   IPC ≈ W / (L + 1)   for W ≤ L
//   IPC → 1.0            for W > L
// where W = warp count and L = exec_latency.
//
// Usage:
//   mini_sm_sim [--warps N] [--exec-latency N] [--cycles N] [--stats-file PATH]
//
// Writes stats to stdout in key=value format.
// If --stats-file is given, the same content is also written to that file
// (compatible with the format read by perf_sweep.py).

#include "mini_sm.h"
#include <iostream>
#include <string>
#include <vector>
#include <optional>
#include <cstring>

using namespace simt;

static void usage() {
    std::cout
        << "Usage: mini_sm_sim [options]\n"
        << "  --warps        N   warp count           (default: 4)\n"
        << "  --exec-latency N   pipeline depth        (default: 4)\n"
        << "  --cycles       N   simulation cycles     (default: 2000)\n"
        << "  --stats-file   P   write stats to file P (default: stdout only)\n";
}

int main(int argc, char* argv[])
{
    // ── Defaults ─────────────────────────────────────────────────────────────
    int warps        = 4;
    int exec_latency = 4;
    int cycles       = 2000;
    std::string stats_file;

    // ── Argument parsing ─────────────────────────────────────────────────────
    for (int i = 1; i < argc; i++) {
        const char* a = argv[i];
        if ((!std::strcmp(a, "--warps")        || !std::strcmp(a, "-w")) && i+1 < argc)
            warps        = std::stoi(argv[++i]);
        else if ((!std::strcmp(a, "--exec-latency") || !std::strcmp(a, "-l")) && i+1 < argc)
            exec_latency = std::stoi(argv[++i]);
        else if ((!std::strcmp(a, "--cycles")  || !std::strcmp(a, "-c")) && i+1 < argc)
            cycles       = std::stoi(argv[++i]);
        else if ((!std::strcmp(a, "--stats-file") || !std::strcmp(a, "-s")) && i+1 < argc)
            stats_file   = argv[++i];
        else if (!std::strcmp(a, "--help") || !std::strcmp(a, "-h")) {
            usage(); return 0;
        }
    }

    // ── Configure and build workload ─────────────────────────────────────────
    Config cfg;
    cfg.warps        = warps;
    cfg.exec_latency = exec_latency;

    // All warps: r0 + r1 → r0   (maximum RAW stress workload)
    std::vector<std::optional<InstrMeta>> warp_instrs(warps);
    for (int w = 0; w < warps; w++) {
        InstrMeta m{};
        m.warp_id = w;
        m.src0    = 0;      // reads r0 — hazard source after each issue
        m.src1    = 1;      // reads r1 — never written, always free
        m.dst     = 0;      // writes r0 — creates the RAW for next issue
        m.has_dst = true;
        warp_instrs[w] = m;
    }

    // ── Run simulation ───────────────────────────────────────────────────────
    MiniSM sm(cfg);
    for (int t = 0; t < cycles; t++)
        sm.tick(warp_instrs);

    // ── Emit stats ───────────────────────────────────────────────────────────
    const auto& c = sm.stats();

    // stdout summary (always printed)
    std::cout
        << "cycles="               << c.cycles               << "\n"
        << "instructions="         << c.instructions         << "\n"
        << "stall_data="           << c.stall_data           << "\n"
        << "stall_structural="     << c.stall_structural      << "\n"
        << "stall_memory="         << c.stall_memory          << "\n"
        << "stall_no_warp="        << c.stall_no_warp         << "\n"
        << "cycles_issuing="       << c.cycles_issuing        << "\n"
        << "wb_count="             << c.wb_count              << "\n"
        << "total_diverge_events=" << c.diverge_events        << "\n"
        << "masked_thread_cycles=" << c.masked_thread_cycles  << "\n"
        << "ipc="                  << c.ipc()                 << "\n"
        << "warp_efficiency="      << c.warp_efficiency()     << "\n";

    // optional file output (same format, compatible with parse_stats() in perf_sweep.py)
    if (!stats_file.empty())
        c.write_file(stats_file);

    return 0;
}
