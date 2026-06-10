# rtl/control/warp_scheduler.sv — Warp Selection Policy (Round Robin)

## What this file does
Chooses which warp to issue each cycle, given:
- warp_ready vector from warp_table
- can_issue info from scoreboard
- optionally warp_has_instr[] from TB source

Policy for Phase-4: Round-robin.

## Where it sits
Instantiated by: `mini_sm_top.sv`

Outputs connect to:
- issue stage (warp_id selected)
- wrap_scheduler wrapper in rtl/top (optional)

## Minimal I/O
Inputs:
- `warp_ready[WARPS]`
- `warp_can_issue[WARPS]`
- `warp_has_instr[WARPS]` (recommended)

Outputs:
- `issue_valid`
- `issue_warp_id`

## Internal state
- `rr_ptr_q` round-robin pointer

## Behavior (Round-robin)
1. Starting from rr_ptr, scan warps circularly
2. Pick the first warp where:
   - warp_ready && warp_can_issue && warp_has_instr
3. If issued:
   - set issue_valid=1
   - rr_ptr <= issue_warp_id + 1 (wrap around)
4. If none eligible:
   - issue_valid=0, rr_ptr holds

## Design rules
- Deterministic selection: makes wave debugging easy.
- Do not output garbage warp_id when issue_valid=0.

## Common bugs
- starvation due to rr_ptr not advancing
- off-by-one wraparound errors
- selecting a warp without an instruction available

## Tests that validate this
- fairness test with multiple always-ready warps
- blocked warp test: scheduler must skip stalled/blocked warp
