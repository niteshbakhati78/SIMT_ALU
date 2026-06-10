# rtl/control/scoreboard.sv — Dependency Tracking (RAW Hazards)

## What this file does
Maintains a `reg_busy[REGS]` table for in-flight destination registers and blocks issue when an instruction reads a busy register (RAW hazard). Clears busy bits on writeback.

## Where it sits
Instantiated by: `mini_sm_top.sv`

Inputs come from:
- Issue stage: src/dst/has_dst when an instruction is issued
- exec_pipe: writeback event (dst reg completed)

Outputs go to:
- scheduler/top: `can_issue` per warp (or per candidate)

## Minimal I/O
Inputs:
- `issue_fire`
- `issue_src0`, `issue_src1`, `issue_dst`, `issue_has_dst`
- `wb_valid`, `wb_dst`, `wb_has_dst` (or just wb_valid + dst if always writes)

Outputs:
- `hazard_src0`, `hazard_src1` (optional for debug)
- `can_issue` (boolean)

## Internal state
- `reg_busy_q[REGS]`
- (optional) `reg_owner_q[REGS]` (warp_id) for debug only

## Behavior
- On issue_fire and has_dst: set `reg_busy[dst]=1`
- When checking can_issue:
  - if `reg_busy[src0]` OR `reg_busy[src1]` => cannot issue
- On wb_valid: clear `reg_busy[wb_dst]=0`

## Design rules / invariants
- Decide ordering when issue and writeback touch same reg in same cycle:
  - Recommended: apply writeback first, then issue sets busy again.
- Only set busy for real destinations (`has_dst=1`).

## Common bugs
- false stalls (wrong busy bit set)
- missed stalls (forgot to check a source)
- stuck busy bit (writeback not clearing)

## Tests that validate this
- dependent chain in one warp must stall until writeback
- two warps: one stalls, other continues issuing (latency hiding)
