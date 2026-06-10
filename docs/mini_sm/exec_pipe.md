# exec_pipe.sv — Purpose & Design Notes

## 1. What this file does
Models multi-cycle execution latency for issued instructions and generates writeback events (wb_valid, wb_warp_id, wb_dst_reg) after a fixed number of cycles.

## 2. Where it sits in the system
- Instantiated by: mini_sm_top.sv
- Connects to:
  - issue stage (accepts issued instruction metadata)
  - scoreboard (writeback clears busy regs)
  - warp_table (optional: marks warp complete/ready)

## 3. Inputs / Outputs
Inputs:
- issue_valid + instruction metadata (warp_id, dst_reg, has_dst, op info)
Outputs:
- wb_valid + metadata
- optional: pipe_full / ready backpressure

## 4. Internal state
- Pipeline shift registers for metadata (depth = LATENCY)
- valid shift register

## 5. Main behaviors
- On issue_valid: push metadata into stage 0
- Shift each cycle
- At last stage: emit wb_valid if valid bit set

## 6. Key rules
- Latency must be consistent and documented (e.g., 4 cycles)
- Decide whether exec_pipe can accept every cycle or needs backpressure

## 7. Common bugs
- Wrong latency (writeback too early/late)
- Metadata misaligned with valid bit
- Dropped writeback events

## 8. Unit tests expected
- Known-latency test (issue at T => wb at T+LAT)
- Stress test with many issues across warps
