"""
perf_sweep.py — Extension 1: Cycle-Accurate Performance Sweep (C++ model)
===========================================================================
Sweeps WARPS × EXEC_LATENCY configurations by calling the C++ mini_sm_sim
binary for each point, then produces three plots:
  1. IPC vs Warp Count  (per exec latency)
  2. Stall Breakdown Heatmap  (% of cycles, at MEM_LATENCIES[2])
  3. Warp Efficiency vs Warp Count

Usage (run from the scripts/ directory OR project root):
  python scripts/perf_sweep.py [--outdir <dir>] [--cycles N] [--sim-binary <path>]

Requires: sim/build/mini_sm_sim.exe  (built via CMake or Makefile cpp_tests target).
Optional: matplotlib + numpy for plots.
"""

import subprocess
import itertools
import json
import argparse
import os
from pathlib import Path

try:
    import matplotlib.pyplot as plt
    import numpy as np
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    print("WARNING: matplotlib not installed — plots will be skipped.")

# ── Paths ──────────────────────────────────────────────────────────────────────

SCRIPT_DIR   = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

# Default location of the compiled C++ binary
DEFAULT_SIM_BINARY = PROJECT_ROOT / "sim" / "build" / "mini_sm_sim.exe"

# MSYS2 ucrt64 bin dir — needed on Windows so the binary can find its DLLs
UCRT64_BIN = Path("C:/msys64/ucrt64/bin")

# ── Sweep parameters ──────────────────────────────────────────────────────────

WARP_COUNTS   = [2, 4, 8, 16]
MEM_LATENCIES = [4, 8, 16, 32]   # maps to EXEC_LATENCY

# ── Helpers ────────────────────────────────────────────────────────────────────

def make_env():
    """Return an env dict with the ucrt64 bin dir prepended to PATH (Windows DLL fix)."""
    env = os.environ.copy()
    if UCRT64_BIN.exists():
        env["PATH"] = str(UCRT64_BIN) + os.pathsep + env.get("PATH", "")
    return env


def run_sim(binary: Path, warps: int, exec_latency: int,
            cycles: int, stats_path: Path) -> tuple[int, str]:
    """Run mini_sm_sim for one (warps, exec_latency) point."""
    cmd = [
        str(binary),
        "--warps",        str(warps),
        "--exec-latency", str(exec_latency),
        "--cycles",       str(cycles),
        "--stats-file",   str(stats_path),
    ]
    result = subprocess.run(
        cmd, capture_output=True, text=True, timeout=60, env=make_env()
    )
    return result.returncode, result.stdout + result.stderr


def parse_stats(filepath: Path) -> dict:
    """Parse key=value stats file into a dict with derived ipc/warp_efficiency."""
    stats = {}
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                key, val = line.split("=", 1)
                try:
                    stats[key.strip()] = int(val.strip())
                except ValueError:
                    try:
                        stats[key.strip()] = float(val.strip())
                    except ValueError:
                        pass

    cycles  = stats.get("cycles",        1)
    instrs  = stats.get("instructions",  0)
    issuing = stats.get("cycles_issuing", 0)

    stats["ipc"]             = instrs / cycles if cycles > 0 else 0.0
    stats["warp_efficiency"] = issuing / cycles * 100.0 if cycles > 0 else 0.0
    stats["stall_breakdown"] = {
        "data_hazard":   stats.get("stall_data",       0) / cycles * 100.0,
        "structural":    stats.get("stall_structural",  0) / cycles * 100.0,
        "memory_latency":stats.get("stall_memory",      0) / cycles * 100.0,
        "no_ready_warp": stats.get("stall_no_warp",     0) / cycles * 100.0,
    }
    return stats


def _zero_stats():
    return {
        "ipc": 0.0, "warp_efficiency": 0.0,
        "stall_breakdown": {k: 0.0 for k in
            ["data_hazard", "structural", "memory_latency", "no_ready_warp"]}
    }

# ── Sweep runner ───────────────────────────────────────────────────────────────

def run_sweep(binary: Path, output_dir: Path, cycles: int) -> dict:
    results = {}

    for warps, mem_lat in itertools.product(WARP_COUNTS, MEM_LATENCIES):
        label      = f"warps={warps:2d}, exec_latency={mem_lat:3d}"
        stats_path = output_dir / f"stats_w{warps}_m{mem_lat}.txt"

        print(f"  Running: {label}  ", end="", flush=True)

        rc, output = run_sim(binary, warps, mem_lat, cycles, stats_path)

        if rc != 0 or not stats_path.exists():
            print(f"FAILED (rc={rc})")
            if output.strip():
                print(f"    {output.strip()[:200]}")
            results[(warps, mem_lat)] = _zero_stats()
            continue

        try:
            stats = parse_stats(stats_path)
            results[(warps, mem_lat)] = stats
            print(f"IPC={stats['ipc']:.3f}  Eff={stats['warp_efficiency']:.1f}%")
        except Exception as e:
            print(f"PARSE FAILED: {e}")
            results[(warps, mem_lat)] = _zero_stats()

    # Save raw results as JSON for reproducibility
    serializable = {f"w{w}_m{m}": v for (w, m), v in results.items()}
    with open(output_dir / "raw_results.json", "w") as f:
        json.dump(serializable, f, indent=2)
    print(f"\n  Raw results saved to {output_dir / 'raw_results.json'}")

    return results

# ── Plot 1: IPC vs Warp Count ──────────────────────────────────────────────────

def plot_ipc_vs_warps(results: dict, output_dir: Path):
    fig, ax = plt.subplots(figsize=(8, 5))
    colors = ["#2196F3", "#4CAF50", "#FF9800", "#F44336"]

    for idx, mem_lat in enumerate(MEM_LATENCIES):
        ipc_vals = [results[(w, mem_lat)]["ipc"] for w in WARP_COUNTS]
        # theoretical IPC: min(W, L+1) / (L+1)
        theory = [min(w, mem_lat + 1) / (mem_lat + 1) for w in WARP_COUNTS]
        ax.plot(WARP_COUNTS, ipc_vals,
                marker="o", linewidth=2, color=colors[idx],
                label=f"EL={mem_lat} (measured)")
        ax.plot(WARP_COUNTS, theory,
                linestyle="--", linewidth=1, color=colors[idx], alpha=0.4)

    ax.set_xlabel("Warp Count", fontsize=12)
    ax.set_ylabel("IPC (Instructions Per Cycle)", fontsize=12)
    ax.set_title("IPC vs Warp Count — Latency Hiding (C++ model)", fontsize=13)
    ax.set_xticks(WARP_COUNTS)
    ax.legend(fontsize=9)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()

    out = output_dir / "ipc_vs_warps.png"
    fig.savefig(out, dpi=150)
    print(f"  Saved: {out}")
    plt.close(fig)

# ── Plot 2: Stall Breakdown Heatmap ───────────────────────────────────────────

def plot_stall_heatmap(results: dict, output_dir: Path):
    mem_lat     = MEM_LATENCIES[2]
    stall_types = ["data_hazard", "structural", "memory_latency", "no_ready_warp"]
    labels      = ["Data Hazard", "Structural", "Mem Latency", "No Ready Warp"]

    data = np.array([
        [results[(w, mem_lat)]["stall_breakdown"].get(s, 0.0) for s in stall_types]
        for w in WARP_COUNTS
    ])

    fig, ax = plt.subplots(figsize=(8, 5))
    im = ax.imshow(data, cmap="YlOrRd", aspect="auto", vmin=0)

    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=30, ha="right")
    ax.set_yticks(range(len(WARP_COUNTS)))
    ax.set_yticklabels([f"{w} warps" for w in WARP_COUNTS])
    ax.set_title(f"Stall Breakdown (% of cycles) — Exec Latency = {mem_lat} cycles",
                 fontsize=12)

    for i in range(len(WARP_COUNTS)):
        for j in range(len(stall_types)):
            ax.text(j, i, f"{data[i, j]:.1f}%",
                    ha="center", va="center", fontsize=9,
                    color="black" if data[i, j] < 50 else "white")

    plt.colorbar(im, ax=ax, label="% of Total Cycles")
    fig.tight_layout()

    out = output_dir / "stall_breakdown_heatmap.png"
    fig.savefig(out, dpi=150)
    print(f"  Saved: {out}")
    plt.close(fig)

# ── Plot 3: Warp Efficiency vs Warp Count ─────────────────────────────────────

def plot_warp_efficiency(results: dict, output_dir: Path):
    fig, ax = plt.subplots(figsize=(8, 5))
    colors = ["#2196F3", "#4CAF50", "#FF9800", "#F44336"]

    for idx, mem_lat in enumerate(MEM_LATENCIES):
        eff = [results[(w, mem_lat)]["warp_efficiency"] for w in WARP_COUNTS]
        ax.plot(WARP_COUNTS, eff,
                marker="s", linewidth=2, color=colors[idx],
                label=f"Exec Latency = {mem_lat} cycles")

    ax.set_xlabel("Warp Count", fontsize=12)
    ax.set_ylabel("Warp Efficiency (%)", fontsize=12)
    ax.set_title("Warp Efficiency vs Warp Count (C++ model)", fontsize=13)
    ax.set_xticks(WARP_COUNTS)
    ax.set_ylim(0, 110)
    ax.axhline(y=100, color="gray", linestyle="--", alpha=0.5, label="100% ceiling")
    ax.legend(fontsize=9)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()

    out = output_dir / "warp_efficiency.png"
    fig.savefig(out, dpi=150)
    print(f"  Saved: {out}")
    plt.close(fig)

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Mini-SM performance sweep (C++ cycle-accurate model)")
    parser.add_argument("--outdir",     default="perf_results",
                        help="Output directory for plots/data (default: perf_results)")
    parser.add_argument("--cycles",     type=int, default=2000,
                        help="Simulation cycles per data point (default: 2000)")
    parser.add_argument("--sim-binary", default=str(DEFAULT_SIM_BINARY),
                        help="Path to mini_sm_sim binary")
    args = parser.parse_args()

    binary     = Path(args.sim_binary)
    output_dir = PROJECT_ROOT / args.outdir
    output_dir.mkdir(exist_ok=True)

    if not binary.exists():
        print(f"ERROR: binary not found: {binary}")
        print("  Build it first: cd sim && cmake -B build -G \"MinGW Makefiles\" && cmake --build build")
        print("  Or run: make cpp_tests  (from project root, with C:\\msys64\\ucrt64\\bin on PATH)")
        return 1

    print("=== Mini-SM Performance Sweep (C++ model) ===")
    print(f"  Warp counts    : {WARP_COUNTS}")
    print(f"  Exec latencies : {MEM_LATENCIES}")
    print(f"  Cycles/point   : {args.cycles}")
    print(f"  Binary         : {binary}")
    print(f"  Output dir     : {output_dir}")
    print()

    results = run_sweep(binary, output_dir, args.cycles)

    if HAS_MATPLOTLIB:
        print("\nGenerating plots...")
        plot_ipc_vs_warps(results, output_dir)
        plot_stall_heatmap(results, output_dir)
        plot_warp_efficiency(results, output_dir)
        print(f"\nAll plots saved to: {output_dir}/")
    else:
        print("\nSkipping plots (matplotlib not available). Install with: pip install matplotlib numpy")

    # IPC summary table
    print("\n--- IPC Summary Table ---")
    header = f"{'Warps':>6}" + "".join(f"  EL={m:>3}" for m in MEM_LATENCIES)
    print(header)
    for w in WARP_COUNTS:
        row = f"{w:>6}"
        for m in MEM_LATENCIES:
            ipc = results.get((w, m), {}).get("ipc", 0.0)
            row += f"   {ipc:.3f}"
        print(row)

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
