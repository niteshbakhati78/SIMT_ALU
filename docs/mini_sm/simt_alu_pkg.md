# simt_alu_pkg.sv — Purpose & Design Notes (Mini-SM Extension)

## 1. What this file does
Defines shared parameters, types, and packed structs used across Mini-SM modules.

## 2. What will be added for Mini-SM
- WARPS, REGS parameters
- warp_state_t enum
- instr_meta_t struct (warp_id, src/dst regs, has_dst, op fields)
- scoreboard helper types

## 3. Key rules
- Keep types stable and reused across modules
- Prefer packed structs for clean pipeline shifting (exec_pipe)
- Keep parameters centralized (LANES, WARPS, REGS)
