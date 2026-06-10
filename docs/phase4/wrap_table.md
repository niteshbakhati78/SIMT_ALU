# rtl/control/warp_table.sv — Warp Context & Readiness

## What this file does
Tracks per-warp state (READY/STALLED) and provides a `warp_ready[]` vector to the scheduler. It also handles transitions when a warp is issued and when it becomes unblocked (e.g., after writeback).

## Where it sits
Instantiated by: `rtl/top/mini_sm_top.sv`

Inputs come from:
- scheduler/issue (a warp was issued)
- scoreboard decisions (warp is blocked/unblocked)
- exec_pipe writeback (warp completed an instruction)

Outputs go to:
- scheduler: `warp_ready[WARPS]`
- top-level debug: `warp_state[WARPS]` (optional)

## Key I/O (high-level)
Inputs:
- `issue_fire` + `issue_warp_id`
- `stall_warp` + `stall_warp_id` (or stall vector)
- `unblock_warp` + `unblock_warp_id` (or unblock vector)

Outputs:
- `warp_ready[WARPS]`

## Internal state
- `warp_state_q[WARPS]`

## Behavior
- Reset: set all warps READY (or only warp0 READY if you want staged bring-up)
- If a warp is stalled -> it must not appear in `warp_ready`
- If a warp is unblocked -> return to READY

## Design rules / invariants
- A warp cannot be issued when STALLED.
- Define priority if stall and unblock happen same cycle (recommend: unblock first, then stall if both asserted).

## Common bugs
- Warp stays stalled forever (unblock condition not wired)
- Warp gets re-issued even though still executing (issue logic not synchronized)

## Tests that validate this
- RAW hazard stall test: warp stalls then returns to READY after writeback
- Scheduler fairness test: multiple READY warps rotate correctly
