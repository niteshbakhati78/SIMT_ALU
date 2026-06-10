// test_mini_sm.cpp
// Three directed tests ported from tb_mini_sm_phase4.sv:
//
//   Test 1 — RAW stall enforcement
//     Warp 0 issues I1 (writes r0). Immediately presents I2 (reads r0).
//     I2 must be blocked for exactly EXEC_LATENCY cycles until wb clears r0.
//
//   Test 2 — Multi-warp latency hiding
//     Warp 0 stalls on I2 (RAW on r0). Warp 1 has non-dependent instructions.
//     During the stall window warp 1 must issue every cycle, proving that
//     multi-warp scheduling hides the execution latency.
//
//   Test 3 — Round-robin fairness
//     All four warps have non-blocking instructions.
//     The scheduler must cycle through warps 0→1→2→3→0→1→2→3 in order.

#include "mini_sm.h"
#include <iostream>
#include <string>
#include <vector>

using namespace simt;

static int g_pass = 0, g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { ++g_pass; std::cout << "  PASS  " << (msg) << "\n"; } \
    else      { ++g_fail; std::cout << "  FAIL  " << (msg) << "\n"; } \
} while(0)

// ── Helpers ────────────────────────────────────────────────────────────────────

static InstrMeta make_instr(int warp, int s0, int s1, int dst, bool has_dst) {
    InstrMeta m{};
    m.warp_id = warp; m.src0 = s0; m.src1 = s1;
    m.dst = dst; m.has_dst = has_dst;
    return m;
}

// Build a warp_instrs vector with nullopt for every warp.
static std::vector<std::optional<InstrMeta>> idle_instrs(int warps) {
    return std::vector<std::optional<InstrMeta>>(warps, std::nullopt);
}

// ── Test 1: RAW stall ──────────────────────────────────────────────────────────
// Expected: I1 issues at tick 0. Warp 0 is then blocked for exactly
// EXEC_LATENCY cycles. I2 issues at tick EXEC_LATENCY + 1.
// stall_data counter must equal EXEC_LATENCY.
void test_raw_stall() {
    std::cout << "\n=== Test 1: RAW stall enforcement ===\n";

    Config cfg;  // WARPS=4, EXEC_LATENCY=4
    MiniSM sm(cfg);

    auto instrs = idle_instrs(cfg.warps);

    // I1: warp 0, r1+r2 → r0   (no dependency yet)
    InstrMeta I1 = make_instr(0, 1, 2, 0, true);
    // I2: warp 0, r0+r3 → r4   (reads r0 → RAW stall against I1)
    InstrMeta I2 = make_instr(0, 0, 3, 4, true);

    // Tick 0: I1 should issue
    instrs[0] = I1;
    auto r0 = sm.tick(instrs);
    CHECK(r0.issued_warp == 0, "tick0: I1 issued on warp 0");

    // Switch to I2. Warp 0 is the only active warp.
    instrs[0] = I2;

    // Ticks 1 … EXEC_LATENCY: all must stall on data hazard
    int stall_cycles = 0;
    for (int t = 1; t <= cfg.exec_latency; t++) {
        auto r = sm.tick(instrs);
        if (!r.issued_warp) stall_cycles++;
    }
    CHECK(stall_cycles == cfg.exec_latency,
          "stalled for exactly EXEC_LATENCY=" + std::to_string(cfg.exec_latency) +
          " cycles (got " + std::to_string(stall_cycles) + ")");

    // Tick EXEC_LATENCY+1: wb has arrived, I2 must now issue
    auto r_issue = sm.tick(instrs);
    CHECK(r_issue.issued_warp == 0, "I2 issued after wb cleared r0");

    // Verify perf counters
    const auto& c = sm.stats();
    CHECK(c.stall_data == (uint64_t)cfg.exec_latency,
          "stall_data == EXEC_LATENCY (" + std::to_string(c.stall_data) + ")");
    CHECK(c.instructions == 2, "exactly 2 instructions issued");
}

// ── Test 2: Multi-warp latency hiding ─────────────────────────────────────────
// Expected: during warp 0's EXEC_LATENCY-cycle stall, warp 1 issues every
// cycle. Total warp 1 issues in the stall window == EXEC_LATENCY.
// Warp 0 must NOT issue during the stall window.
void test_latency_hiding() {
    std::cout << "\n=== Test 2: Multi-warp latency hiding ===\n";

    Config cfg;
    MiniSM sm(cfg);

    auto instrs = idle_instrs(cfg.warps);

    InstrMeta I1  = make_instr(0, 1, 2, 0, true);  // warp0: r1+r2→r0
    InstrMeta I2  = make_instr(0, 0, 3, 4, true);  // warp0: r0+r3→r4 (RAW)
    // warp1: r5+r6→r7, non-dependent — issues freely every cycle
    InstrMeta I_w1 = make_instr(1, 5, 6, 7, true);

    instrs[0] = I1;
    instrs[1] = I_w1;

    // Tick 0: warp 0 should issue I1 (rr_ptr starts at 0)
    auto r0 = sm.tick(instrs);
    CHECK(r0.issued_warp == 0, "tick0: warp 0 issues I1");

    // Switch warp 0 to I2
    instrs[0] = I2;

    // Ticks 1 … EXEC_LATENCY: warp 0 stalled, warp 1 hides latency
    int w0_issues = 0, w1_issues = 0;
    for (int t = 1; t <= cfg.exec_latency; t++) {
        auto r = sm.tick(instrs);
        if (r.issued_warp == 0) w0_issues++;
        if (r.issued_warp == 1) w1_issues++;
    }
    CHECK(w0_issues == 0,
          "warp 0 never issues during stall window");
    CHECK(w1_issues == cfg.exec_latency,
          "warp 1 issues " + std::to_string(w1_issues) +
          " times (expected " + std::to_string(cfg.exec_latency) + ")");

    // At least 3× IPC improvement vs single-warp case
    // single-warp IPC over this window ≈ 1/(EXEC_LATENCY+1)
    // two-warp IPC over this window ≈ EXEC_LATENCY/(EXEC_LATENCY+1)
    double ipc_window = static_cast<double>(w1_issues) / cfg.exec_latency;
    CHECK(ipc_window >= 0.9,
          "latency-hiding IPC >= 0.9 in stall window (got " +
          std::to_string(ipc_window).substr(0, 5) + ")");
}

// ── Test 3: Round-robin fairness ───────────────────────────────────────────────
// All four warps have non-blocking instructions.
// Expected issue order for 8 consecutive issues: 0,1,2,3,0,1,2,3.
void test_round_robin() {
    std::cout << "\n=== Test 3: Round-robin fairness ===\n";

    Config cfg;
    MiniSM sm(cfg);

    // has_dst=false: no busy bits set, warps always eligible
    auto instrs = idle_instrs(cfg.warps);
    for (int w = 0; w < cfg.warps; w++)
        instrs[w] = make_instr(w, 5, 6, 7, false);

    std::vector<int> observed;
    int ticks_needed = cfg.warps * 2 + 4;  // enough for 8 issues + margin

    for (int t = 0; t < ticks_needed && (int)observed.size() < cfg.warps * 2; t++) {
        auto r = sm.tick(instrs);
        if (r.issued_warp) observed.push_back(*r.issued_warp);
    }

    CHECK((int)observed.size() == cfg.warps * 2,
          "collected " + std::to_string(observed.size()) + " issues");

    bool order_ok = true;
    for (int i = 0; i < (int)observed.size(); i++) {
        int expected = i % cfg.warps;
        if (observed[i] != expected) { order_ok = false; break; }
    }
    CHECK(order_ok, "round-robin order: 0,1,2,3,0,1,2,3");

    // Print the observed order for inspection
    std::cout << "  Observed issue order: ";
    for (int w : observed) std::cout << w << " ";
    std::cout << "\n";

    // Warp efficiency should be 100% with no stalls
    const auto& c = sm.stats();
    CHECK(c.stall_data == 0,    "no data-hazard stalls");
    CHECK(c.stall_no_warp == 0, "no no-ready-warp stalls");
    double eff = c.warp_efficiency();
    CHECK(eff == 100.0,
          "warp efficiency = 100% (got " + std::to_string(eff).substr(0, 5) + "%)");
}

// ── Main ───────────────────────────────────────────────────────────────────────
int main() {
    test_raw_stall();
    test_latency_hiding();
    test_round_robin();

    std::cout << "\n========================================\n";
    std::cout << "  Passed: " << g_pass
              << "  Failed: " << g_fail << "\n";
    std::cout << "  RESULT: " << (g_fail == 0 ? "PASS" : "FAIL") << "\n";
    std::cout << "========================================\n";
    return g_fail > 0 ? 1 : 0;
}
