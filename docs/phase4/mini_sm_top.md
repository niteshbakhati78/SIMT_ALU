# rtl/top/mini_sm_top.sv — Phase-4 Integration Top

## What this file does
Wires together:
- warp_table
- scoreboard
- warp_scheduler
- exec_pipe
- existing simt_alu

It is the single module the Phase-4 testbench targets.

## Where it sits
- RTL entrypoint for Phase-4 testing: `testbench/phase4/...`

## Inputs/Outputs (Phase-4)
Inputs from TB (recommended):
- per-warp instruction availability and fields:
  - warp_has_instr[WARPS]
  - instr_meta per warp (src/dst/sel/mask)
  - operands per warp (a,b arrays)

Outputs to TB:
- issued warp_id + issue_valid (debug)
- performance counters: issue_count, stall_count, wb_count
- optional: reg_busy bitmap, warp_state vector

## Main behavior (per cycle)
1. Determine which warps are eligible (ready + has_instr + scoreboard allows)
2. Scheduler selects a warp to issue
3. Drive selected warp’s ALU fields to `simt_alu` inputs
4. On issue_fire:
   - scoreboard marks dst busy
   - exec_pipe enqueues metadata
   - warp_table may mark warp waiting (optional)
5. On writeback:
   - scoreboard clears dst busy
   - warp_table unblocks warp (if stalled)

## Design rules
- Only 1 warp issues per cycle (Phase-4 simplification)
- Deterministic priorities when multiple events happen same cycle
- Keep existing SIMT ALU unchanged; integrate around it

## Debug checklist
- Verify issue_valid, issue_warp_id first
- Verify reg_busy toggles on issue / clears on wb
- Verify wb timing matches EXEC_LATENCY
- Verify warp_ready drops when stalled and rises after wb

## Phase-4 tests that validate this
- RAW dependency stall test
- two-warp latency hiding test (IPC improvement)
- fairness test
