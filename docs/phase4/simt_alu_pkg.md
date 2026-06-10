# rtl/pkg/simt_alu_pkg.sv — Phase 4 Mini-SM Package

## What this file does
Defines shared parameters, enums, and packed structs used across the Mini-SM modules (scheduler, scoreboard, exec pipe, top).

## Why we need it
Right now `simt_alu_pkg.sv` is empty. In Phase-4 we need a single place for:
- number of warps, architectural regs
- warp state encoding
- instruction metadata fields (warp_id, src/dst regs, etc.)
- common typedefs so modules connect cleanly

## Proposed contents (Phase-4)
### Parameters
- `LANES` (already used elsewhere)
- `DATA_WIDTH` (already used elsewhere)
- `WARPS` (new) — default 4
- `REGS` (new) — default 16
- `EXEC_LATENCY` (new) — default 4

### Enums
- `warp_state_t`: READY / STALLED / (optional) WAITING / DONE

### Structs
- `instr_meta_t` (minimum):
  - `warp_id`
  - `src0`, `src1`, `dst` (reg indices)
  - `has_dst` (1 if writes register)
  - `sel` (your ALU op select)
  - `lane_mask` (per-lane active mask)

(Operands `a` and `b` can be passed separately from TB; we only need metadata in the scoreboard/exec_pipe.)

## Design rules
- Keep `instr_meta_t` packed so it can shift through `exec_pipe` easily.
- Keep defaults small (`WARPS=4`, `REGS=16`) to simplify debugging and TB.

## Debug tips
- Put `warp_id/src/dst/has_dst` into waves early; these are the first signals to verify.
