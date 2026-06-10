# warp_scheduler.sv — Purpose & Design Notes

## 1. What this file does
Selects which warp issues an instruction each cycle based on readiness and scoreboard availability, using a deterministic policy (round-robin recommended first).

## 2. Where it sits in the system
- Instantiated by: mini_sm_top.sv
- Connects to:
  - warp_table (warp_ready)
  - scoreboard (can_issue)
  - issue stage (issue_warp_id, issue_valid)

## 3. Inputs / Outputs
Inputs:
- warp_ready[WARPS]
- can_issue_per_warp[WARPS] (or can_issue for candidate)
- optional: warp_has_instr[WARPS]
Outputs:
- issue_valid
- issue_warp_id
- next_rr_ptr (internal)

## 4. Internal state
- rr_ptr_q (round-robin pointer)

## 5. Main behaviors
- Each cycle, search warps starting at rr_ptr for first eligible warp
- If found: assert issue_valid, output warp_id, advance rr_ptr to warp_id+1
- If none: issue_valid=0 and rr_ptr holds

## 6. Key rules
- Must not issue from non-ready warp
- Policy must be deterministic for debugging

## 7. Common bugs
- Starvation due to rr_ptr not advancing
- Issuing invalid warp_id when none eligible
- Off-by-one in rr_ptr wraparound

## 8. Unit tests expected
- Fairness test with multiple always-ready warps
- Stall-resume test where one warp is blocked and later becomes eligible
