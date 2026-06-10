// test_warp_table.cpp — Unit tests for simt::WarpTable
#include "warp_table.h"
#include <iostream>
#include <string>

using namespace simt;

static int g_pass = 0, g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { ++g_pass; std::cout << "  PASS  " << (msg) << "\n"; } \
    else      { ++g_fail; std::cout << "  FAIL  " << (msg) << "\n"; } \
} while(0)

// All warps start in the READY state.
void test_initial_all_ready() {
    Config cfg;
    WarpTable wt(cfg);
    for (int w = 0; w < cfg.warps; w++)
        CHECK(wt.is_ready(w), "warp " + std::to_string(w) + " initially READY");
}

// set_stalled / set_ready round-trip.
void test_stall_and_ready() {
    Config cfg;
    WarpTable wt(cfg);
    wt.set_stalled(2);
    CHECK(!wt.is_ready(2), "warp2 STALLED after set_stalled");
    CHECK( wt.is_ready(0), "warp0 unaffected by warp2 stall");
    CHECK( wt.is_ready(3), "warp3 unaffected by warp2 stall");
    wt.set_ready(2);
    CHECK( wt.is_ready(2), "warp2 READY after set_ready");
}

// Stalling all warps then using reset() restores everything.
void test_all_stalled_then_reset() {
    Config cfg;
    WarpTable wt(cfg);
    for (int w = 0; w < cfg.warps; w++) wt.set_stalled(w);
    for (int w = 0; w < cfg.warps; w++)
        CHECK(!wt.is_ready(w), "warp " + std::to_string(w) + " STALLED");
    wt.reset();
    for (int w = 0; w < cfg.warps; w++)
        CHECK(wt.is_ready(w),
              "warp " + std::to_string(w) + " READY after reset");
}

// Transitions are idempotent.
void test_idempotent_transitions() {
    Config cfg;
    WarpTable wt(cfg);
    wt.set_stalled(1);
    wt.set_stalled(1);  // second stall call is a no-op
    CHECK(!wt.is_ready(1), "double set_stalled: still STALLED");
    wt.set_ready(1);
    wt.set_ready(1);    // second ready call is a no-op
    CHECK( wt.is_ready(1), "double set_ready: still READY");
}

// Warps are fully independent — stalling one must not change others.
void test_warp_independence() {
    Config cfg;
    WarpTable wt(cfg);
    wt.set_stalled(0);
    wt.set_stalled(2);
    CHECK(!wt.is_ready(0), "warp0 STALLED");
    CHECK( wt.is_ready(1), "warp1 READY (untouched)");
    CHECK(!wt.is_ready(2), "warp2 STALLED");
    CHECK( wt.is_ready(3), "warp3 READY (untouched)");
    wt.set_ready(0);
    CHECK( wt.is_ready(0), "warp0 back to READY");
    CHECK(!wt.is_ready(2), "warp2 still STALLED");
}

int main() {
    std::cout << "=== WarpTable Tests ===\n";
    test_initial_all_ready();
    test_stall_and_ready();
    test_all_stalled_then_reset();
    test_idempotent_transitions();
    test_warp_independence();
    std::cout << "\n  Passed: " << g_pass
              << "  Failed: " << g_fail << "\n";
    return g_fail > 0 ? 1 : 0;
}
