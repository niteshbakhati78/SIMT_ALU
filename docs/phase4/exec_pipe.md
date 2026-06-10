# rtl/core/exec_pipe.sv — Fixed-Latency Execution + Writeback Generator

## What this file does
Models multi-cycle execution latency for issued instructions.
It shifts `instr_meta_t` through a pipeline of depth EXEC_LATENCY and emits a writeback event at the end.

This makes scoreboard + stalls meaningful even if the SIMT ALU is combinational.

## Where it sits
Instantiated by: `mini_sm_top.sv`

Inputs:
- issue_fire + instr metadata (warp_id, dst, has_dst)

Outputs:
- wb_valid
- wb_warp_id
- wb_dst
- wb_has_dst (if needed)

## Internal state
- valid shift register [EXEC_LATENCY]
- metadata shift register [EXEC_LATENCY] (packed struct recommended)

## Behavior
- On issue_fire: load stage0 valid=1 and metadata
- Each cycle: shift valid+metadata forward
- When last stage valid=1: assert wb_valid and output metadata fields

## Design rules
- Metadata must stay aligned with valid bit at all times.
- Define whether exec_pipe always accepts every cycle (Phase-4: yes, simplest).
- EXEC_LATENCY must match testbench assumptions.

## Common bugs
- writeback occurs at wrong cycle (latency mismatch)
- metadata shifts but valid does not (misalignment)
- dropped writebacks under back-to-back issue

## Tests that validate this
- fixed latency check: issue at T => wb at T+LAT
- stress test: back-to-back issues from different warps
