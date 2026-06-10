# Phase 4 Mini-SM Testbench Plan

## Purpose
Validate scheduling + scoreboard behavior:
- RAW hazard stall and release
- Latency hiding across warps
- Scheduler fairness

## Tests
1. Single warp dependent sequence -> stalls until writeback
2. Two warps alternating -> IPC improves vs single warp
3. One warp permanently blocked -> other warps continue
4. Stress test: randomized instruction stream with scoreboard checks

## Success criteria
- No incorrect issue when hazards exist
- Writeback timing matches exec_pipe latency
- rr scheduler covers all ready warps
- Performance counters behave as expected
