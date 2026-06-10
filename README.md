# SIMT GPU Streaming Multiprocessor Model

A pre-silicon functional model of a GPU Streaming Multiprocessor (SM) front-end, implemented in both **SystemVerilog RTL** and a **cycle-accurate C++ software model**. The project covers warp scheduling, scoreboard-based hazard detection, fixed-latency execution pipelines, and Post-Dominator (PDOM) thread-mask divergence handling.

Built as an architecture exploration testbed to quantify latency hiding, occupancy requirements, and stall behavior across microarchitectural configurations.

---

## Architecture Overview

The SM front-end is composed of five hardware modules that map 1-to-1 between the RTL and C++ model:

```
  Warp Instructions
  (one per warp slot)
         |
         v
  +------+--------+       +-------------+
  |  WarpScheduler |<------| WarpTable   |  (ready/stalled per warp)
  |  (round-robin) |       +-------------+
  +-------+--------+
          |  issued_warp
          v
  +-------+--------+       +-------------+
  |    Scoreboard  |       |  ExecPipe   |  (shift-register pipeline)
  |  (busy bits    |<---wb-| depth=L     |
  |   per warp)    |       +-------------+
  +----------------+
          |
          v
  +-------+--------+
  |    PdomCtrl    |  (per warp: THEN-first reconvergence stack)
  |  active_mask   |
  +----------------+
          |
          v
     MiniSM (top-level tick() integrates all five modules)
```

**Scheduling policy:** Round-robin across eligible warps. A warp is eligible when it has a pending instruction, is in READY state, and its source registers are not busy in the scoreboard.

**Hazard policy:** Scoreboard marks the destination register busy on issue. The register is cleared when writeback exits the execution pipeline after `exec_latency` cycles. Read-After-Write (RAW) stalls are enforced by the scheduler checking `can_issue` before the writeback clears the scoreboard.

**Divergence policy:** THEN-first PDOM. On a divergent branch, the ELSE-path mask is pushed onto the per-warp reconvergence stack and the THEN path executes first. On `path_done`, the stack is popped (one-cycle registered latency modeled in both RTL and C++) and the ELSE path executes. When the stack is empty, the warp reconverges to the full lane mask.

---

## Repository Structure

```
SIMT_ALU/
│
├── rtl/                          SystemVerilog RTL
│   ├── pkg/
│   │   └── simt_alu_pkg.sv       Package: parameters, types
│   ├── basic/                    Full adder, mux, comparator
│   ├── core/
│   │   ├── simd_lane_alu.sv      Per-lane ALU (ADD/SUB/AND/OR/XOR/SLT/SLL/SRL)
│   │   ├── simt_alu_core.sv      8-lane SIMD ALU core
│   │   ├── simt_stack.sv         Parameterized PDOM stack
│   │   └── exec_pipe.sv          Fixed-latency execution pipeline
│   ├── control/
│   │   ├── warp_scheduler.sv     Round-robin warp arbiter
│   │   ├── scoreboard.sv         Per-warp register busy bits
│   │   ├── wrap_table.sv         Warp ready/stalled state
│   │   └── pdom_ctrl.sv          Per-warp PDOM reconvergence controller
│   └── top/
│       └── mini_sm_top.sv        Top-level SM integration
│
├── sim/                          C++ cycle-accurate functional model
│   ├── include/
│   │   ├── simt_types.h          Config, InstrMeta, WbResult, PerfCounters
│   │   ├── scoreboard.h
│   │   ├── warp_table.h
│   │   ├── warp_scheduler.h
│   │   ├── exec_pipe.h
│   │   ├── mini_sm.h
│   │   └── pdom_ctrl.h
│   ├── src/
│   │   ├── simt_types.cpp        PerfCounters write_file()
│   │   ├── scoreboard.cpp
│   │   ├── warp_table.cpp
│   │   ├── warp_scheduler.cpp
│   │   ├── exec_pipe.cpp
│   │   ├── mini_sm.cpp
│   │   ├── pdom_ctrl.cpp
│   │   └── main.cpp              CLI binary: mini_sm_sim
│   ├── tests/
│   │   ├── test_scoreboard.cpp   22 assertions
│   │   ├── test_warp_table.cpp   24 assertions
│   │   ├── test_mini_sm.cpp      14 assertions
│   │   └── test_divergence.cpp   31 assertions
│   └── CMakeLists.txt
│
├── testbench/                    SystemVerilog testbenches
│   ├── phase1/                   SIMT ALU directed + random tests
│   ├── phase2/                   Predicate mask unit
│   ├── phase2.5/                 Exec mask update
│   ├── phase3/                   SIMT stack and branch control
│   └── phase4/
│       ├── tb_mini_sm_phase4.sv  3 directed SM integration tests
│       ├── tb_divergence_phase4.sv  4 PDOM divergence tests
│       └── tb_perf_sweep.sv      RAW-heavy sweep workload
│
├── scripts/
│   └── perf_sweep.py             16-config performance sweep driver
│
└── Makefile                      ModelSim ASE build targets
```

---

## Building the C++ Model

### Requirements

- GCC 14+ with C++17 support
- On Windows: [MSYS2](https://www.msys2.org/) with the `ucrt64` toolchain

```bash
# Install ucrt64 toolchain via MSYS2 (one time)
pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake
```

Add `C:\msys64\ucrt64\bin` to your PATH before building.

### Build

```bash
cd sim
cmake -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

This produces four test binaries and the simulation CLI in `sim/build/`.

---

## Running the Tests

Run each test suite individually:

```bash
sim/build/test_scoreboard.exe
sim/build/test_warp_table.exe
sim/build/test_mini_sm.exe
sim/build/test_divergence.exe
```

Or run all tests through CTest:

```bash
cd sim/build
ctest --output-on-failure
```

Expected result: **91/91 assertions passing** across all four suites.

| Suite | Assertions | Covers |
|---|---|---|
| test_scoreboard | 22 | Busy-bit set/clear, per-warp isolation, reset |
| test_warp_table | 24 | Ready/stalled transitions, independence, reset |
| test_mini_sm | 14 | RAW stall enforcement, latency hiding, round-robin fairness |
| test_divergence | 31 | THEN-first policy, no-divergence path, two-warp independence, masked-thread-cycles counter |

---

## Running the Performance Sweep

```bash
python scripts/perf_sweep.py --cycles 5000
```

This runs the C++ model across all 16 (warp count x execution latency) configurations and writes results to `perf_results/`.

Optional arguments:

```
--outdir   <path>   output directory for plots and JSON  (default: perf_results)
--cycles   <N>      simulation cycles per data point     (default: 2000)
--sim-binary <path> path to mini_sm_sim binary
```

### Workload

All warps continuously issue the instruction `r0 + r1 -> r0`. This creates the maximum possible RAW stall pressure: every warp writes `r0` on each issue and must wait `exec_latency` cycles before it can read `r0` again. This workload isolates the latency-hiding benefit of increasing warp count.

### Sweep Results (5000 cycles per point)

```
 Warps   EL=4    EL=8   EL=16   EL=32
     2  0.400   0.222   0.118   0.061
     4  0.800   0.445   0.236   0.122
     8  1.000   0.889   0.471   0.243
    16  1.000   1.000   0.941   0.486
```

IPC follows the analytical bound `W / (L + 1)` (capped at 1.0), where W is warp count and L is execution latency. Key findings:

- 8 warps fully hide a 4-cycle execution latency, achieving 1.0 IPC (2.5x over single-warp)
- 16 warps are required to approach saturation at 16-cycle depth (0.94 IPC)
- At EL=32, even 16 warps only recover 48.6% efficiency, indicating occupancy is the binding constraint

The sweep completes in under 1 second. An equivalent ModelSim RTL simulation of the same configurations takes approximately 3 minutes.

### Output Files

```
perf_results/
├── raw_results.json            all stats for all 16 configurations
├── stats_w<W>_m<L>.txt         per-point stats (cycles, IPC, stall breakdown)
├── ipc_vs_warps.png            IPC scaling curves with theoretical overlay
├── stall_breakdown_heatmap.png stall type breakdown as % of cycles
└── warp_efficiency.png         warp efficiency vs warp count
```

---

## Running the RTL Simulation (ModelSim ASE)

Requires Intel ModelSim ASE installed at `C:/intelFPGA/20.1/modelsim_ase/`.

```bash
# Run a specific phase
make phase4        # Mini-SM integration tests
make divergence    # PDOM divergence tests

# Run all phases
make all
```

Available targets:

| Target | Testbench | Description |
|---|---|---|
| phase1 | tb_simt_alu | SIMT ALU directed and random tests |
| phase2 | tb_predicate_mask_phase2 | Predicate mask unit |
| phase2_5 | tb_exec_mask_update | Exec mask update |
| phase3_stack | tb_simt_stack_phase3 | SIMT reconvergence stack |
| phase3_branch | tb_branch_control_phase3 | Branch control |
| phase4 | tb_mini_sm_phase4 | Full SM integration |
| divergence | tb_divergence_phase4 | PDOM divergence and reconvergence |

---

## Key Design Decisions

**Posedge-correct tick() ordering in the C++ model**

The `MiniSM::tick()` method snapshots `can_issue` from the scoreboard *before* calling `exec_pipe_.tick()` and updating the scoreboard. This matches the RTL `always_ff` semantics where the issue decision is based on the pre-posedge scoreboard state, and writeback clears the register in the same cycle the snapshot was already taken. Reversing this order would allow a warp to issue one cycle too early.

**One-cycle pop latency in PdomCtrl**

The RTL `simt_stack` module has registered outputs: the popped mask is available one cycle after the pop signal is asserted. `PdomCtrl` models this with a `POP_WAIT` FSM state that saves the popped entry in `pop_pending_` during the path-done cycle and applies it to `curr_mask` on the following cycle. This is why the active mask reflects the ELSE path two ticks after `path_done`, not one.

**THEN-first divergence policy**

When a branch produces both a non-zero then-mask and a non-zero else-mask, the ELSE-path mask is pushed onto the PDOM stack and the THEN path executes immediately. This matches the execution model used in NVIDIA GPU architectures where the taken path runs first.

**Runtime-parameterized Config**

All hardware parameters (warp count, register count, lane count, execution latency, PDOM stack depth) are runtime values stored in a `Config` struct rather than compile-time templates. This allows the same binary to sweep all configurations without recompilation, which is the key enabler for the fast Python sweep.

---

## Performance Model vs RTL Parity

The C++ model and SystemVerilog RTL produce identical behavior on all shared test scenarios:

| Scenario | RTL result | C++ model result |
|---|---|---|
| RAW stall cycles (EL=4) | 4 stall cycles | 4 stall cycles |
| THEN-path mask (cond=0xCA) | 0xCA | 0xCA |
| ELSE-path mask after pop | 0x35 | 0x35 |
| Round-robin order (4 warps) | 0,1,2,3,0,1,2,3 | 0,1,2,3,0,1,2,3 |
| IPC at W=8, EL=4 (RTL sweep) | 0.995 | 1.000 |

The small IPC difference at W=8/EL=4 is due to startup transients in the RTL sweep running fewer total cycles. Both converge to the same steady-state value.

---

## Skills Demonstrated

- Cycle-accurate hardware modeling in C++ (functional parity with RTL)
- SystemVerilog RTL design and simulation (ModelSim ASE)
- Scoreboard-based hazard detection and warp scheduling
- PDOM thread-mask divergence handling
- Structured test plan development and directed verification
- Performance telemetry instrumentation (IPC, warp efficiency, stall classification)
- Python-driven microarchitectural sweep and analysis
- CMake build system and cross-platform toolchain configuration
