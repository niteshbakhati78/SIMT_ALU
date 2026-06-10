# SIMT ALU Architecture (FPGA-First, Mini-SM Ready)

## Goal
Implement a parameterized SIMT (Single-Instruction, Multiple-Thread) ALU in SystemVerilog and run it on an Arty-7 100T FPGA. The design models warp-style execution: one opcode is applied across multiple lanes, with per-lane predication via a lane mask.

This project is scoped so the SIMT ALU can later plug directly into a "mini-SM" (warp scheduler + register file + scoreboard + SIMT stack + LSU).

## Top-Level Concept
A single "warp instruction" enters the ALU:
- opcode: operation type (ADD, SUB, etc.)
- lane_mask: which lanes are active (predicated on)
- src_a/src_b: vector operands, one element per lane

The ALU produces:
- result vector (one element per lane)
- per-lane flags (start with zero flag)

## Interfaces
### Data + Control Inputs
- opcode[3:0]
- lane_mask[LANES-1:0]
- src_a[LANES][DATA_W]
- src_b[LANES][DATA_W]

### Outputs
- result[LANES][DATA_W]
- zero_flag[LANES]

### Handshake (Scheduler-Friendly)
- in_valid / in_ready
- out_valid / out_ready

v1 behavior (initial):
- in_ready = 1 always (no internal stalls)
- out_valid mirrors in_valid (combinational datapath)

Later (v2/v3):
- add pipeline stages + valid-bit propagation
- support backpressure (in_ready depends on internal pipeline availability)

## Microarchitecture Blocks
1) simt_alu_pkg.sv
   - opcodes, typedefs, helper functions/constants

2) simd_lane_alu.sv
   - 1-lane ALU function/module implementing arithmetic/logic ops

3) simt_alu_core.sv
   - lane loop (for i in 0..LANES-1)
   - applies predication rule using lane_mask[i]
   - computes per-lane flags

4) simt_alu.sv (top)
   - wires handshake and core together
   - provides a stable interface for later mini-SM integration

## Predication Rule (v1)
If lane_mask[i] == 1:
- result[i] = ALU(opcode, src_a[i], src_b[i])

If lane_mask[i] == 0:
- lane is inactive; result[i] passes through src_a[i]
This models "no-write" semantics at the execution-unit output (simple and deterministic).

## FPGA Considerations (Arty A7-100T)
- DATA_W=32 and LANES=8 is reasonable.
- MUL will infer DSP blocks; result uses lower DATA_W bits.
- v1 may meet timing at modest clocks; v2 pipelining will improve Fmax.
- A later FPGA demo wrapper will stream vectors from BRAM into the SIMT ALU and write results back to BRAM, with cycle counters for performance reporting.
