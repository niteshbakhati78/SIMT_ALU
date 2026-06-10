// test_divergence.cpp
// Four directed tests ported from tb_divergence_phase4.sv:
//
//  Test 1 — Single-warp branch divergence, THEN-first
//    Branch with cond=0xCA on 8-lane warp (curr_mask=0xFF).
//    then_mask=0xCA, else_mask=0x35.
//    Expected sequence:
//      1 tick  after branch  → active_mask=0xCA, diverged=true
//      2 ticks after path_done(THEN) → active_mask=0x35 (ELSE path)
//      1 tick  after path_done(ELSE) → active_mask=0xFF (reconverged)
//
//  Test 2 — No divergence (uniform condition, cond=0xFF)
//    then_mask=0xFF, else_mask=0x00 → no push.
//    active_mask stays 0xFF, diverged=false throughout.
//
//  Test 3 — Two warps diverge independently
//    Warp-0: cond=0xF0 → then=0xF0, else=0x0F
//    Warp-1: cond=0x0F → then=0x0F, else=0xF0
//    Masks must differ; each warp's PdomCtrl is unaffected by the other's.
//
//  Test 4 — masked_thread_cycles increments during divergence
//    After branch (cond=0xCA), 4 lanes are masked each cycle.
//    Over 5 idle ticks the accumulated masked-thread-cycles == 5*4 = 20.

#include "pdom_ctrl.h"
#include <iostream>
#include <string>

using namespace simt;

static int g_pass = 0, g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { ++g_pass; std::cout << "  PASS  " << (msg) << "\n"; } \
    else      { ++g_fail; std::cout << "  FAIL  " << (msg) << "\n"; } \
} while(0)

// ── Helpers ────────────────────────────────────────────────────────────────────

static PdomInput idle_input() { return PdomInput{}; }

static PdomInput branch_input(uint32_t cond, uint32_t pc = 0x0300) {
    PdomInput in;
    in.branch_fire   = true;
    in.branch_cond   = cond;
    in.reconverge_pc = pc;
    return in;
}

static PdomInput path_done_input() {
    PdomInput in;
    in.path_done = true;
    return in;
}

static int popcount(uint32_t v) {
    int n = 0;
    while (v) { n += v & 1; v >>= 1; }
    return n;
}

// ── Test 1: Single-warp branch divergence ─────────────────────────────────────
void test_single_divergence() {
    std::cout << "\n=== Test 1: Single-warp branch divergence (THEN-first) ===\n";

    Config cfg;  // lanes=8, pdom_depth=8
    PdomCtrl pdom(cfg);

    const uint32_t FULL    = 0xFF;
    const uint32_t COND    = 0xCA;
    const uint32_t EXP_THEN = COND & FULL;    // 0xCA
    const uint32_t EXP_ELSE = (~COND) & FULL; // 0x35

    // ── Branch fires ──────────────────────────────────────────────────────────
    // Tick B: branch fires.  Output reflects pre-branch state (mask=0xFF).
    auto r_branch = pdom.tick(branch_input(COND, 0x0300));
    CHECK(r_branch.active_mask == FULL, "tick_B: active_mask=0xFF before branch updates");
    CHECK(!r_branch.diverged,           "tick_B: not yet diverged (before update)");

    // Tick B+1: registers have updated → THEN mask is now active.
    auto r_then = pdom.tick(idle_input());
    CHECK(r_then.active_mask == EXP_THEN,
          "tick_B+1: active_mask=0xCA (THEN path)");
    CHECK(r_then.diverged,
          "tick_B+1: diverged=true (ELSE path on stack)");

    // Two idle cycles: warp executes THEN-path instructions
    pdom.tick(idle_input());
    pdom.tick(idle_input());

    // ── THEN path done ────────────────────────────────────────────────────────
    // Tick P: path_done fires → state→POP_WAIT, pop is saved in pop_pending_.
    auto r_pd1 = pdom.tick(path_done_input());
    CHECK(r_pd1.active_mask == EXP_THEN, "tick_P: active_mask still 0xCA (output before update)");

    // Tick P+1: POP_WAIT state fires → curr_mask ← else_mask.
    // Output still shows old curr_mask (THEN), but sp is now 0 → diverged=false.
    auto r_popwait = pdom.tick(idle_input());
    CHECK(!r_popwait.diverged, "tick_P+1: diverged=false (stack empty after pop decrement)");

    // Tick P+2: ELSE mask is now in curr_mask → visible in output.
    auto r_else = pdom.tick(idle_input());
    CHECK(r_else.active_mask == EXP_ELSE,
          "tick_P+2: active_mask=0x35 (ELSE path after pop)");
    CHECK(!r_else.diverged, "tick_P+2: diverged=false (no more deferred paths)");

    // Two idle cycles: warp executes ELSE-path instructions
    pdom.tick(idle_input());
    pdom.tick(idle_input());

    // ── ELSE path done: stack empty → full reconvergence ─────────────────────
    // Tick Q: path_done fires with stack empty → curr_mask ← 0xFF immediately.
    pdom.tick(path_done_input());

    // Tick Q+1: reconverged mask is in output.
    auto r_conv = pdom.tick(idle_input());
    CHECK(r_conv.active_mask == FULL,
          "tick_Q+1: active_mask=0xFF (fully reconverged)");
    CHECK(!r_conv.diverged, "tick_Q+1: diverged=false after reconvergence");
}

// ── Test 2: No divergence (uniform condition) ─────────────────────────────────
void test_no_divergence() {
    std::cout << "\n=== Test 2: No divergence (uniform condition cond=0xFF) ===\n";

    Config cfg;
    PdomCtrl pdom(cfg);

    const uint32_t FULL = 0xFF;

    // Branch with all lanes taken → else_mask=0x00 → no push
    auto r0 = pdom.tick(branch_input(0xFF, 0x0400));
    CHECK(r0.active_mask == FULL, "tick_B: active_mask=0xFF (before update)");

    // After update: then_mask=0xFF → curr_mask=0xFF, sp unchanged (no push)
    auto r1 = pdom.tick(idle_input());
    CHECK(r1.active_mask == FULL, "tick_B+1: active_mask=0xFF (no divergence)");
    CHECK(!r1.diverged,           "tick_B+1: diverged=false (no push)");
    CHECK(r1.stack_empty,         "tick_B+1: stack_empty=true");

    // Branch with no lanes taken (cond=0x00) → then_mask=0x00, else_mask=0xFF
    // Only else_mask non-zero → curr_mask=0xFF (the else mask), still no push
    pdom.tick(branch_input(0x00, 0x0450));
    pdom.tick(idle_input()); // let it settle
    auto r3 = pdom.tick(idle_input());
    CHECK(r3.active_mask == FULL, "all-not-taken: active_mask=0xFF (else path, no push)");
    CHECK(!r3.diverged,           "all-not-taken: diverged=false");
}

// ── Test 3: Two warps diverge independently ───────────────────────────────────
void test_two_warps_independent() {
    std::cout << "\n=== Test 3: Two warps diverge independently ===\n";

    Config cfg;
    PdomCtrl pdom0(cfg);   // warp 0
    PdomCtrl pdom1(cfg);   // warp 1

    // Both warps fire their branches in the same cycle
    pdom0.tick(branch_input(0xF0, 0x0500));  // then=0xF0, else=0x0F
    pdom1.tick(branch_input(0x0F, 0x0600));  // then=0x0F, else=0xF0

    // One tick later: both masks should have updated independently
    auto r0 = pdom0.tick(idle_input());
    auto r1 = pdom1.tick(idle_input());

    const uint32_t FULL = 0xFF;

    CHECK(r0.active_mask == (0xF0 & FULL),
          "warp0 active_mask=0xF0 (THEN path)");
    CHECK(r1.active_mask == (0x0F & FULL),
          "warp1 active_mask=0x0F (THEN path)");
    CHECK(r0.active_mask != r1.active_mask,
          "warp masks differ — independence verified");
    CHECK(r0.diverged, "warp0 diverged=true");
    CHECK(r1.diverged, "warp1 diverged=true");

    // Reconverge warp 0: THEN done → POP_WAIT → ELSE → ELSE done → full mask
    pdom0.tick(path_done_input());          // P: state→POP_WAIT
    pdom0.tick(idle_input());               // P+1: curr_mask←0x0F
    auto r0_else = pdom0.tick(idle_input());// P+2: output shows else mask
    CHECK(r0_else.active_mask == (0x0F & FULL),
          "warp0 ELSE path mask=0x0F after pop");

    pdom0.tick(path_done_input());          // Q: stack empty → curr_mask←0xFF
    auto r0_conv = pdom0.tick(idle_input());
    CHECK(r0_conv.active_mask == FULL,
          "warp0 reconverged to 0xFF");
    CHECK(!r0_conv.diverged, "warp0 diverged=false after reconvergence");

    // Warp 1 must be unaffected by warp 0's path_done calls
    // It should still show its THEN mask (0x0F) and be diverged
    CHECK(r1.diverged, "warp1 still diverged after warp0 ops");
    auto r1_check = pdom1.tick(idle_input());
    CHECK(r1_check.active_mask == (0x0F & FULL),
          "warp1 mask still 0x0F — unaffected by warp0 reconvergence");
}

// ── Test 4: masked_thread_cycles counter ─────────────────────────────────────
void test_masked_thread_cycles() {
    std::cout << "\n=== Test 4: masked_thread_cycles counter ===\n";

    Config cfg;  // lanes=8
    PdomCtrl pdom(cfg);

    const uint32_t FULL    = (1u << cfg.lanes) - 1;
    const uint32_t COND    = 0xCA;
    const uint32_t EXP_THEN = COND & FULL;  // 0xCA — 4 lanes active, 4 masked

    int masked_lanes_per_cycle = popcount(FULL ^ EXP_THEN); // = 4

    // Fire branch
    pdom.tick(branch_input(COND, 0x0700));

    // 5 idle ticks while warp executes THEN path — each tick 4 lanes are masked
    uint64_t mtc = 0;
    for (int t = 0; t < 5; t++) {
        auto r = pdom.tick(idle_input());
        if (r.diverged) {
            // Masked lanes = lanes not in active_mask
            mtc += popcount(FULL ^ r.active_mask);
        }
    }

    CHECK(mtc > 0,
          "masked_thread_cycles > 0 during divergence (got " +
          std::to_string(mtc) + ")");
    CHECK(mtc == (uint64_t)(5 * masked_lanes_per_cycle),
          "masked_thread_cycles == 5*4=20 (got " + std::to_string(mtc) + ")");

    // Reconverge: THEN done → pop → ELSE mask active
    pdom.tick(path_done_input());  // P
    pdom.tick(idle_input());       // P+1
    auto r_else = pdom.tick(idle_input()); // P+2

    uint32_t EXP_ELSE = (~COND) & FULL;
    CHECK(r_else.active_mask == EXP_ELSE,
          "active_mask=0x35 on ELSE path after pop");

    // ELSE done → reconverge
    pdom.tick(path_done_input());
    auto r_conv = pdom.tick(idle_input());
    CHECK(r_conv.active_mask == FULL, "reconverged to full mask after ELSE done");

    // After reconvergence there should be no more masked lanes
    auto r_post = pdom.tick(idle_input());
    uint64_t mtc_post = 0;
    if (r_post.diverged)
        mtc_post += popcount(FULL ^ r_post.active_mask);
    CHECK(mtc_post == 0, "no masked lanes after full reconvergence");
}

// ── Main ───────────────────────────────────────────────────────────────────────
int main() {
    test_single_divergence();
    test_no_divergence();
    test_two_warps_independent();
    test_masked_thread_cycles();

    std::cout << "\n========================================\n";
    std::cout << "  Passed: " << g_pass
              << "  Failed: " << g_fail << "\n";
    std::cout << "  RESULT: " << (g_fail == 0 ? "PASS" : "FAIL") << "\n";
    std::cout << "========================================\n";
    return g_fail > 0 ? 1 : 0;
}
