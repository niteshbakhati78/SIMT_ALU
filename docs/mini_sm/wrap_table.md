# warp_table.sv — Purpose & Design Notes

## 1. What this file does
Stores per-warp context/state for the Mini-SM (READY/STALLED, optional PC, active mask, etc.) and provides “warp readiness” info to the scheduler.

## 2. Where it sits in the system
- Instantiated by: mini_sm_top.sv
- Instantiates: none (pure storage/control)
- Connects to:
  - warp_scheduler (reports READY warps)
  - issue logic (marks warp as issued/stalled)
  - scoreboard/writeback (releases stalled warps when hazards clear)

## 3. Inputs / Outputs (high level)
Inputs:
- clk, rst
- issue events (warp_id issued)
- stall/un-stall events
- optional mask updates (e.g., divergence/reconvergence)

Outputs:
- warp_ready[WARPS]
- warp_state[WARPS]
- per-warp stored fields (mask, pc, etc.)

## 4. Internal state
- warp_state_q[WARPS]
- optional: pc_q[WARPS]
- optional: exec_mask_q[WARPS]

## 5. Main behaviors
- On reset: initializes all warps to READY (or a defined starting state)
- On issue: may mark warp as BUSY/WAITING depending on pipeline model
- On stall: warp becomes STALLED (not eligible for scheduling)
- On release: warp returns to READY

## 6. Key rules
- Scheduler must never see a warp as READY if it is STALLED/WAITING.
- State updates must be deterministic if stall + writeback occur same cycle (define priority).

## 7. Common bugs
- Warp stuck STALLED forever (missing release condition)
- Warp incorrectly re-issued while still executing

## 8. Unit tests expected
- RAW hazard stall test (warp stalls then releases)
- Fairness test (scheduler cycles through READY warps)
