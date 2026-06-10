# scoreboard.sv — Purpose & Design Notes

## 1. What this file does
Tracks in-flight destination registers and blocks issuing instructions that would read a busy register (RAW hazard). Clears busy bits on writeback.

## 2. Where it sits in the system
- Instantiated by: mini_sm_top.sv
- Connects to:
  - issue stage (checks can_issue)
  - exec_pipe/writeback (clears busy regs)

## 3. Inputs / Outputs
Inputs:
- issue_valid + (src regs, dst reg, has_dst)
- wb_valid + (dst reg written back)
Outputs:
- can_issue (for a candidate instruction / warp)
- optional: stall_reason / hazard flags for debug

## 4. Internal state
- reg_busy_q[REGS] (1 if register is in-flight)
- optional: reg_owner_q[REGS] (warp_id) for debug

## 5. Main behaviors
- On issue with has_dst: set reg_busy[dst]=1
- On can_issue check: if src0 or src1 busy => block
- On writeback: clear reg_busy[wb_dst]=0

## 6. Key rules
- Busy bits must clear only on a real writeback event.
- Decide ordering when issue and writeback for same reg happen same cycle (usually writeback first, then issue sets it again).

## 7. Common bugs
- False stalls (marking wrong reg busy)
- Missed stalls (forgetting to check src regs)
- Never-clearing busy bits (writeback not wired)

## 8. Unit tests expected
- RAW hazard test across warps
- Back-to-back dependent instruction test within a warp
