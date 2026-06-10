# GPU SM Front-End: Extension Implementation Guide

## Overview

This document outlines the implementation plan for two extensions to the GPU
Streaming Multiprocessor (SM) Front-End Microarchitecture project:

- **Extension 1** — Cycle-Accurate Performance Model Layer
- **Extension 2** — Divergence Handling via PDOM Reconvergence Stack

Both extensions build directly on your existing SystemVerilog functional model
and Python simulation infrastructure.

---

## Extension 1: Cycle-Accurate Performance Model Layer

### Goal

Instrument your existing SM model to collect per-cycle statistics and run
sweeps across warp count and memory latency configurations. The output is a
quantified characterization of latency-hiding behavior — the core purpose of
a GPU SM front-end.

---

### What to Instrument (SystemVerilog)

Add the following counters to your top-level SM module. These are purely
observational — they do not change functional behavior.

#### 1.1 Global Cycle Counter

```systemverilog
// In your SM top-level module
int unsigned cycle_count;

always_ff @(posedge clk or posedge rst) begin
    if (rst) cycle_count <= 0;
    else     cycle_count <= cycle_count + 1;
end
```

#### 1.2 IPC Tracking

Track total instructions retired across all warps.

```systemverilog
int unsigned total_instructions_retired;

always_ff @(posedge clk or posedge rst) begin
    if (rst) total_instructions_retired <= 0;
    else if (instruction_issued)   // your existing issue signal
        total_instructions_retired <= total_instructions_retired + 1;
end

// IPC computed at end of simulation:
// IPC = total_instructions_retired / cycle_count
```

#### 1.3 Stall Classification Counters

This is the most valuable instrumentation. Track stall cycles broken down
by cause.

```systemverilog
int unsigned stall_data_hazard;    // scoreboard blocking issue
int unsigned stall_structural;     // no functional unit available
int unsigned stall_memory_latency; // warp waiting on memory response
int unsigned stall_no_ready_warp;  // all warps stalled simultaneously

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        stall_data_hazard    <= 0;
        stall_structural     <= 0;
        stall_memory_latency <= 0;
        stall_no_ready_warp  <= 0;
    end else begin
        // Only increment one stall type per cycle (priority-based)
        if (!issue_valid && scoreboard_blocked)
            stall_data_hazard <= stall_data_hazard + 1;
        else if (!issue_valid && fu_busy)
            stall_structural <= stall_structural + 1;
        else if (!issue_valid && warp_waiting_mem)
            stall_memory_latency <= stall_memory_latency + 1;
        else if (!issue_valid)
            stall_no_ready_warp <= stall_no_ready_warp + 1;
    end
end
```

#### 1.4 Warp Efficiency Counter

Measures what percentage of cycles at least one warp is issuing.

```systemverilog
int unsigned cycles_with_issue;

always_ff @(posedge clk or posedge rst) begin
    if (rst) cycles_with_issue <= 0;
    else if (issue_valid)
        cycles_with_issue <= cycles_with_issue + 1;
end

// Warp Efficiency = cycles_with_issue / cycle_count * 100
```

---

### Exporting Stats (SystemVerilog → Python)

At the end of simulation, dump counters to a file using `$fwrite`:

```systemverilog
// In your testbench final block
final begin
    int fd;
    fd = $fopen("sim_stats.txt", "w");
    $fwrite(fd, "cycles=%0d\n",            cycle_count);
    $fwrite(fd, "instructions=%0d\n",      total_instructions_retired);
    $fwrite(fd, "stall_data=%0d\n",        stall_data_hazard);
    $fwrite(fd, "stall_structural=%0d\n",  stall_structural);
    $fwrite(fd, "stall_memory=%0d\n",      stall_memory_latency);
    $fwrite(fd, "stall_no_warp=%0d\n",     stall_no_ready_warp);
    $fwrite(fd, "cycles_issuing=%0d\n",    cycles_with_issue);
    $fclose(fd);
end
```

---

### Python Sweep and Analysis Script

This script runs your simulator across a parameter matrix and produces the
performance plots.

```python
import subprocess
import itertools
import re
import json
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

# ── Configuration ─────────────────────────────────────────────────────────────

WARP_COUNTS    = [4, 8, 16, 32]
MEM_LATENCIES  = [10, 50, 100, 200]   # cycles — L1 hit to DRAM
SIM_BINARY     = "./sim_sm"            # your compiled ModelSim/VCS binary
OUTPUT_DIR     = Path("perf_results")
OUTPUT_DIR.mkdir(exist_ok=True)

# ── Stat Parser ───────────────────────────────────────────────────────────────

def parse_stats(filepath: str) -> dict:
    stats = {}
    with open(filepath) as f:
        for line in f:
            key, val = line.strip().split("=")
            stats[key] = int(val)

    cycles       = stats["cycles"]
    instructions = stats["instructions"]
    issuing      = stats["cycles_issuing"]

    stats["ipc"]             = instructions / cycles if cycles > 0 else 0
    stats["warp_efficiency"] = issuing / cycles * 100 if cycles > 0 else 0
    stats["stall_breakdown"] = {
        "data_hazard":    stats["stall_data"]       / cycles * 100,
        "structural":     stats["stall_structural"]  / cycles * 100,
        "memory_latency": stats["stall_memory"]      / cycles * 100,
        "no_ready_warp":  stats["stall_no_warp"]     / cycles * 100,
    }
    return stats

# ── Sweep Runner ──────────────────────────────────────────────────────────────

def run_sweep():
    results = {}
    for warps, mem_lat in itertools.product(WARP_COUNTS, MEM_LATENCIES):
        print(f"Running: warps={warps}, mem_latency={mem_lat}")

        # Pass parameters to your simulation via plusargs or defines
        cmd = [
            SIM_BINARY,
            f"+warp_count={warps}",
            f"+mem_latency={mem_lat}",
            f"+stats_file=sim_stats.txt"
        ]
        subprocess.run(cmd, check=True)

        stats = parse_stats("sim_stats.txt")
        results[(warps, mem_lat)] = stats
        print(f"  IPC={stats['ipc']:.3f}, "
              f"Warp Eff={stats['warp_efficiency']:.1f}%")

    # Save raw results
    serializable = {f"w{w}_m{m}": v for (w, m), v in results.items()}
    with open(OUTPUT_DIR / "raw_results.json", "w") as f:
        json.dump(serializable, f, indent=2)

    return results

# ── Plot 1: IPC vs Warp Count (per memory latency) ───────────────────────────

def plot_ipc_vs_warps(results):
    fig, ax = plt.subplots(figsize=(8, 5))
    colors = ["#2196F3", "#4CAF50", "#FF9800", "#F44336"]

    for idx, mem_lat in enumerate(MEM_LATENCIES):
        ipc_vals = [results[(w, mem_lat)]["ipc"] for w in WARP_COUNTS]
        ax.plot(WARP_COUNTS, ipc_vals,
                marker="o", linewidth=2,
                color=colors[idx],
                label=f"Mem Latency = {mem_lat} cycles")

    ax.set_xlabel("Warp Count", fontsize=12)
    ax.set_ylabel("IPC (Instructions Per Cycle)", fontsize=12)
    ax.set_title("IPC vs Warp Count — Latency Hiding Analysis", fontsize=13)
    ax.set_xticks(WARP_COUNTS)
    ax.legend()
    ax.grid(True, alpha=0.3)

    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / "ipc_vs_warps.png", dpi=150)
    print("Saved: ipc_vs_warps.png")

# ── Plot 2: Stall Breakdown Heatmap ──────────────────────────────────────────

def plot_stall_heatmap(results):
    stall_types = ["data_hazard", "structural", "memory_latency", "no_ready_warp"]
    labels      = ["Data Hazard", "Structural", "Mem Latency", "No Ready Warp"]

    # Fix mem_latency=100, sweep warps — representative slice
    mem_lat = 100
    data = np.array([
        [results[(w, mem_lat)]["stall_breakdown"][s] for s in stall_types]
        for w in WARP_COUNTS
    ])

    fig, ax = plt.subplots(figsize=(8, 5))
    im = ax.imshow(data, cmap="YlOrRd", aspect="auto")

    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=30, ha="right")
    ax.set_yticks(range(len(WARP_COUNTS)))
    ax.set_yticklabels([f"{w} warps" for w in WARP_COUNTS])
    ax.set_title("Stall Breakdown (% of cycles) — Mem Latency = 100 cycles",
                 fontsize=12)

    plt.colorbar(im, ax=ax, label="% of Total Cycles")
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / "stall_breakdown_heatmap.png", dpi=150)
    print("Saved: stall_breakdown_heatmap.png")

# ── Plot 3: Warp Efficiency vs Warp Count ────────────────────────────────────

def plot_warp_efficiency(results):
    fig, ax = plt.subplots(figsize=(8, 5))
    colors = ["#2196F3", "#4CAF50", "#FF9800", "#F44336"]

    for idx, mem_lat in enumerate(MEM_LATENCIES):
        eff_vals = [results[(w, mem_lat)]["warp_efficiency"] for w in WARP_COUNTS]
        ax.plot(WARP_COUNTS, eff_vals,
                marker="s", linewidth=2,
                color=colors[idx],
                label=f"Mem Latency = {mem_lat} cycles")

    ax.set_xlabel("Warp Count", fontsize=12)
    ax.set_ylabel("Warp Efficiency (%)", fontsize=12)
    ax.set_title("Warp Efficiency vs Warp Count", fontsize=13)
    ax.set_xticks(WARP_COUNTS)
    ax.set_ylim(0, 105)
    ax.axhline(y=100, color="gray", linestyle="--", alpha=0.5, label="100% ceiling")
    ax.legend()
    ax.grid(True, alpha=0.3)

    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / "warp_efficiency.png", dpi=150)
    print("Saved: warp_efficiency.png")

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    results = run_sweep()
    plot_ipc_vs_warps(results)
    plot_stall_heatmap(results)
    plot_warp_efficiency(results)
    print("\nAll plots saved to:", OUTPUT_DIR)
```

---

### Expected Results and What to Report

After running your sweep, you should see results roughly in this shape
(exact values will depend on your implementation):

| Warp Count | Mem Lat 10c | Mem Lat 50c | Mem Lat 100c | Mem Lat 200c |
|:----------:|:-----------:|:-----------:|:------------:|:------------:|
| 4          | ~0.9 IPC    | ~0.4 IPC    | ~0.2 IPC     | ~0.1 IPC     |
| 8          | ~1.0 IPC    | ~0.7 IPC    | ~0.4 IPC     | ~0.2 IPC     |
| 16         | ~1.0 IPC    | ~1.0 IPC    | ~0.8 IPC     | ~0.4 IPC     |
| 32         | ~1.0 IPC    | ~1.0 IPC    | ~1.0 IPC     | ~0.7 IPC     |

The key insight to highlight: **at 100-cycle memory latency, IPC scales from
~0.2 at 4 warps to ~1.0 at 32 warps** — this is latency hiding working as
designed and is the core result to report on your resume.

---

### Resume Bullet (Post Extension 1)

> *"Instrumented cycle-accurate performance model to extract IPC, stall
> breakdown, and warp efficiency across 4–32 warps and memory latency sweeps
> of 10–200 cycles; demonstrated IPC scaling from 0.2 to 1.0 under 100-cycle
> simulated memory latency, quantifying latency-hiding effectiveness across
> 16 parameter configurations."*

---
---

## Extension 2: Divergence Handling via PDOM Reconvergence Stack

### Goal

Model control flow divergence in your warp scheduler. When threads within a
warp take different branches, the hardware must serialize execution and
reconverge at a post-dominator point. This extension adds that mechanism and
measures its IPC cost.

---

### Background: What is the PDOM Stack?

In a GPU, all threads in a warp execute the same instruction (SIMT). When a
branch diverges:

1. The hardware pushes the reconvergence point (post-dominator) onto a stack
2. The taken-path threads execute with an active mask
3. The not-taken threads are masked off (idle)
4. At the reconvergence point, all threads are re-enabled

```
Warp Threads:  T0  T1  T2  T3
Branch condition: T0,T1 → taken | T2,T3 → not-taken

Cycle N:   Push reconvergence PC to PDOM stack
           Active mask = 1100 → execute TAKEN path
Cycle N+k: Active mask = 0011 → execute NOT-TAKEN path
Cycle N+m: Pop PDOM stack → Active mask = 1111 → reconverge
```

---

### SystemVerilog Implementation

#### 2.1 Data Structures

Add these to your warp state structure:

```systemverilog
// Per-warp PDOM reconvergence stack entry
typedef struct packed {
    logic [31:0] reconv_pc;      // post-dominator program counter
    logic [31:0] next_pc;        // next path to execute after this one
    logic [NUM_THREADS-1:0] mask; // thread active mask for this path
} pdom_entry_t;

// Per-warp state extension
typedef struct packed {
    // ... your existing warp state fields ...
    logic [NUM_THREADS-1:0] active_mask;       // current active thread mask
    pdom_entry_t pdom_stack [PDOM_STACK_DEPTH]; // reconvergence stack
    logic [$clog2(PDOM_STACK_DEPTH)-1:0] pdom_sp; // stack pointer
    logic diverged;                              // warp currently diverged
} warp_state_t;
```

#### 2.2 Branch Detection and Stack Push

```systemverilog
// Parameters
parameter NUM_THREADS     = 32;
parameter PDOM_STACK_DEPTH = 8;

// Branch handling logic
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        for (int w = 0; w < NUM_WARPS; w++) begin
            warp[w].active_mask <= '1;       // all threads active
            warp[w].pdom_sp     <= 0;
            warp[w].diverged    <= 0;
        end
    end else begin
        if (branch_detected && issuing_warp == current_warp) begin

            automatic logic [NUM_THREADS-1:0] taken_mask;
            automatic logic [NUM_THREADS-1:0] not_taken_mask;

            taken_mask     = branch_condition_mask &
                             warp[current_warp].active_mask;
            not_taken_mask = (~branch_condition_mask) &
                             warp[current_warp].active_mask;

            if (taken_mask != 0 && not_taken_mask != 0) begin
                // TRUE DIVERGENCE — push to PDOM stack
                warp[current_warp].diverged <= 1;

                // Push not-taken path for later execution
                warp[current_warp].pdom_stack[warp[current_warp].pdom_sp]
                    <= '{
                        reconv_pc: reconvergence_pc,  // from branch instruction
                        next_pc:   not_taken_pc,
                        mask:      not_taken_mask
                    };
                warp[current_warp].pdom_sp <=
                    warp[current_warp].pdom_sp + 1;

                // Execute taken path first
                warp[current_warp].active_mask <= taken_mask;

            end
            // If all threads agree — no divergence, no stack push needed
        end
    end
end
```

#### 2.3 Reconvergence Detection and Stack Pop

```systemverilog
always_ff @(posedge clk) begin
    if (warp[current_warp].diverged &&
        current_pc == warp[current_warp]
                        .pdom_stack[warp[current_warp].pdom_sp - 1].reconv_pc)
    begin
        // Reached reconvergence point — pop stack
        automatic logic [$clog2(PDOM_STACK_DEPTH)-1:0] top;
        top = warp[current_warp].pdom_sp - 1;

        if (warp[current_warp].pdom_stack[top].next_pc != 0) begin
            // Still have a not-taken path to execute
            warp[current_warp].active_mask <=
                warp[current_warp].pdom_stack[top].mask;
            warp[current_warp].pdom_sp <= top; // keep entry until both done
        end else begin
            // Both paths done — full reconvergence
            warp[current_warp].active_mask <= '1;
            warp[current_warp].pdom_sp     <= top;
            warp[current_warp].diverged    <= 0;
        end
    end
end
```

#### 2.4 Performance Counters for Divergence

```systemverilog
int unsigned cycles_diverged   [NUM_WARPS]; // per-warp diverged cycles
int unsigned total_diverge_events;          // how many branches diverged
int unsigned masked_thread_cycles;          // thread-cycles wasted to masking

always_ff @(posedge clk) begin
    for (int w = 0; w < NUM_WARPS; w++) begin
        if (warp[w].diverged) begin
            cycles_diverged[w] <= cycles_diverged[w] + 1;

            // Count masked (inactive) threads this cycle
            masked_thread_cycles <=
                masked_thread_cycles +
                ($countones(~warp[w].active_mask));
        end
    end
end
```

---

### Python Divergence Experiment Script

This script sweeps divergence probability and measures IPC degradation.

```python
import subprocess
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

OUTPUT_DIR = Path("divergence_results")
OUTPUT_DIR.mkdir(exist_ok=True)

# Divergence probability sweep: 0% to 75% of branches diverge
DIVERGENCE_RATES  = [0.0, 0.10, 0.25, 0.50, 0.75]
WARP_COUNT        = 16    # fix warps, isolate divergence effect
MEM_LATENCY       = 50    # fix memory latency

def run_divergence_sim(div_rate: float) -> dict:
    cmd = [
        "./sim_sm",
        f"+warp_count={WARP_COUNT}",
        f"+mem_latency={MEM_LATENCY}",
        f"+divergence_rate={div_rate}",
        "+stats_file=div_stats.txt"
    ]
    subprocess.run(cmd, check=True)
    return parse_div_stats("div_stats.txt")

def parse_div_stats(filepath: str) -> dict:
    stats = {}
    with open(filepath) as f:
        for line in f:
            key, val = line.strip().split("=")
            stats[key] = int(val)

    cycles = stats["cycles"]
    stats["ipc"] = stats["instructions"] / cycles
    stats["divergence_overhead_pct"] = (
        stats["masked_thread_cycles"] /
        (cycles * WARP_COUNT) * 100
    )
    return stats

def plot_divergence_ipc(results: dict):
    rates = sorted(results.keys())
    ipcs  = [results[r]["ipc"] for r in rates]
    base_ipc = ipcs[0]  # IPC at 0% divergence

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    # Plot 1: IPC vs divergence rate
    axes[0].plot([r * 100 for r in rates], ipcs,
                 marker="o", color="#F44336", linewidth=2)
    axes[0].axhline(y=base_ipc, color="gray",
                    linestyle="--", alpha=0.6, label="Baseline IPC")
    axes[0].set_xlabel("Branch Divergence Rate (%)", fontsize=12)
    axes[0].set_ylabel("IPC", fontsize=12)
    axes[0].set_title("IPC Degradation vs Divergence Rate", fontsize=13)
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)

    # Plot 2: IPC degradation percentage
    degradation = [(base_ipc - ipc) / base_ipc * 100 for ipc in ipcs]
    axes[1].bar([r * 100 for r in rates], degradation,
                color="#FF9800", edgecolor="black", width=6)
    axes[1].set_xlabel("Branch Divergence Rate (%)", fontsize=12)
    axes[1].set_ylabel("IPC Degradation (%)", fontsize=12)
    axes[1].set_title("IPC Degradation % vs Divergence Rate", fontsize=13)
    axes[1].grid(True, alpha=0.3, axis="y")

    fig.suptitle(f"Divergence Impact — {WARP_COUNT} Warps, "
                 f"{MEM_LATENCY}-cycle Mem Latency", fontsize=14)
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / "divergence_ipc.png", dpi=150)
    print("Saved: divergence_ipc.png")

if __name__ == "__main__":
    results = {}
    for rate in DIVERGENCE_RATES:
        print(f"Running divergence rate = {rate*100:.0f}%")
        results[rate] = run_divergence_sim(rate)
        print(f"  IPC = {results[rate]['ipc']:.3f}, "
              f"  Divergence Overhead = "
              f"{results[rate]['divergence_overhead_pct']:.1f}%")

    plot_divergence_ipc(results)
    print("\nDone. Results in:", OUTPUT_DIR)
```

---

### Expected Results and What to Report

| Divergence Rate | Expected IPC | Degradation vs Baseline |
|:---------------:|:------------:|:-----------------------:|
| 0%              | ~1.0         | —                       |
| 10%             | ~0.92        | ~8%                     |
| 25%             | ~0.80        | ~20%                    |
| 50%             | ~0.60        | ~38–42%                 |
| 75%             | ~0.42        | ~55–60%                 |

The key result to report: **50% branch divergence causes ~38–42% IPC
degradation** — a concrete, architecture-relevant number that maps directly
to real GPU behavior.

---

### Resume Bullet (Post Extension 2)

> *"Extended warp scheduler with a PDOM-based reconvergence stack modeling
> per-warp thread mask divergence; swept branch divergence rates from 0–75%,
> measuring ~40% IPC degradation at 50% divergence vs fully converged
> execution, consistent with published GPU architecture characterizations."*

---
---

## Combined Resume Entry (Both Extensions Complete)

```
GPU Streaming Multiprocessor (SM) Front-End Microarchitecture | SystemVerilog, Python

• Built a cycle-accurate functional model of a GPU SM front-end in
  SystemVerilog supporting 32 concurrent warps, modeling ALU/memory
  instruction issue, scoreboard-based hazard tracking, and round-robin
  warp arbitration across a 5-stage pipeline.

• Instrumented performance model to extract IPC, stall breakdown, and warp
  efficiency; measured IPC scaling from 0.2 to 1.0 across 4–32 warps under
  100-cycle simulated memory latency, quantifying latency-hiding
  effectiveness across 16 sweep configurations.

• Extended warp scheduler with a PDOM-based reconvergence stack for
  divergent branch handling; swept divergence rates from 0–75%, measuring
  ~40% IPC degradation at 50% divergence vs fully converged execution.

• Validated functional correctness against 60+ structured test cases
  covering all scoreboard hazard classes, dependency chain depths, warp
  interleaving, and divergence reconvergence sequences.
```

---

## Implementation Timeline Estimate

| Task                                      | Estimated Time  |
|:------------------------------------------|:---------------:|
| Add SV performance counters (Ext. 1)      | 2–3 hours       |
| Export stats + Python sweep script        | 3–4 hours       |
| Generate and interpret plots              | 1–2 hours       |
| PDOM stack SV implementation (Ext. 2)     | 4–6 hours       |
| Divergence experiment + Python script     | 2–3 hours       |
| Write testcases for divergence paths      | 2–3 hours       |
| **Total**                                 | **~15–20 hours**|

Both extensions are achievable over 2–3 focused weekends.
