# mini_sm_top.sv — Purpose & Design Notes

## 1. What this file does
Top-level integration for the Mini-SM. Wires together warp_table, warp_scheduler, scoreboard, exec_pipe, and the existing simt_alu.

## 2. Where it sits in the system
- Instantiated by: testbench phase4_mini_sm
- Instantiates:
  - warp_table
  - warp_scheduler
  - scoreboard
  - exec_pipe
  - simt_alu (existing)

## 3. Inputs / Outputs
Inputs:
- clk, rst
- instruction sources (from TB trace generator or simple ROM interface)
Outputs:
- status/perf counters (issue_count, stall_count, wb_count)
- optional debug signals (selected warp, hazard flags)

## 4. Internal state
- Perf counters
- Instruction selection muxing per warp

## 5. Main behaviors
- Determine eligible warps (warp_ready + has_instr + scoreboard allows)
- Select warp via scheduler
- Issue instruction metadata to exec_pipe and operands/control to simt_alu
- Use writeback events to update scoreboard and warp_table
- Maintain counters

## 6. Key rules
- Only 1 warp can issue per cycle (for this simplified model)
- Deterministic behavior on simultaneous events (issue + writeback)

## 7. Common bugs
- Wiring mismatch between scheduler outputs and issue stage
- Scoreboard not receiving correct dst_reg/has_dst
- Warp_table state not transitioning correctly

## 8. Unit tests expected
- All phase4 tests run through this top
