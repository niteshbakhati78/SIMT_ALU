// test_scoreboard.cpp — Unit tests for simt::Scoreboard
#include "scoreboard.h"
#include <iostream>
#include <string>

using namespace simt;

static int g_pass = 0, g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { ++g_pass; std::cout << "  PASS  " << (msg) << "\n"; } \
    else      { ++g_fail; std::cout << "  FAIL  " << (msg) << "\n"; } \
} while(0)

// All registers start clear — any source pair should be issuable.
void test_initial_state() {
    Config cfg;
    Scoreboard sb(cfg);
    CHECK(sb.can_issue(0,  0,  1), "initial: warp0 can issue r0+r1");
    CHECK(sb.can_issue(3, 15, 14), "initial: warp3 can issue r15+r14");
    CHECK(sb.can_issue(1,  0,  0), "initial: same-register source pair OK");
}

// Marking a register busy blocks any instruction that reads it as src0 or src1.
void test_mark_blocks_source() {
    Config cfg;
    Scoreboard sb(cfg);
    sb.mark_busy(0, 5);
    CHECK(!sb.can_issue(0, 5, 1), "warp0 blocked: src0=r5 busy");
    CHECK(!sb.can_issue(0, 1, 5), "warp0 blocked: src1=r5 busy");
    CHECK( sb.can_issue(0, 1, 2), "warp0 free: neither src uses r5");
}

// Clearing a busy register restores issuability.
void test_clear_unblocks() {
    Config cfg;
    Scoreboard sb(cfg);
    sb.mark_busy(0, 3);
    CHECK(!sb.can_issue(0, 3, 0), "blocked before clear");
    sb.clear(0, 3);
    CHECK( sb.can_issue(0, 3, 0), "unblocked after clear");
}

// Busy bits are per-warp — one warp's state must not affect another.
void test_warp_isolation() {
    Config cfg;
    Scoreboard sb(cfg);
    for (int r = 0; r < cfg.regs; r++) sb.mark_busy(0, r);
    CHECK(!sb.can_issue(0, 0, 1), "warp0 fully blocked");
    CHECK( sb.can_issue(1, 0, 1), "warp1 independent of warp0");
    CHECK( sb.can_issue(2, 5, 5), "warp2 independent");
    CHECK( sb.can_issue(3, 7, 8), "warp3 independent");
}

// Multiple registers busy simultaneously — both must be clear to issue.
void test_multiple_busy_regs() {
    Config cfg;
    Scoreboard sb(cfg);
    sb.mark_busy(1, 2);
    sb.mark_busy(1, 7);
    CHECK(!sb.can_issue(1, 2, 7), "blocked: both srcs busy");
    CHECK(!sb.can_issue(1, 0, 7), "blocked: src1=r7 busy");
    CHECK(!sb.can_issue(1, 2, 0), "blocked: src0=r2 busy");
    CHECK( sb.can_issue(1, 0, 1), "free: neither r2 nor r7");
    sb.clear(1, 2);
    CHECK(!sb.can_issue(1, 2, 7), "still blocked: r7 still busy");
    sb.clear(1, 7);
    CHECK( sb.can_issue(1, 2, 7), "free: both cleared");
}

// Reset clears all warps.
void test_reset() {
    Config cfg;
    Scoreboard sb(cfg);
    for (int w = 0; w < cfg.warps; w++)
        for (int r = 0; r < cfg.regs; r++)
            sb.mark_busy(w, r);
    sb.reset();
    for (int w = 0; w < cfg.warps; w++)
        CHECK(sb.can_issue(w, 0, 1),
              "warp " + std::to_string(w) + " clear after reset");
}

int main() {
    std::cout << "=== Scoreboard Tests ===\n";
    test_initial_state();
    test_mark_blocks_source();
    test_clear_unblocks();
    test_warp_isolation();
    test_multiple_busy_regs();
    test_reset();
    std::cout << "\n  Passed: " << g_pass
              << "  Failed: " << g_fail << "\n";
    return g_fail > 0 ? 1 : 0;
}
