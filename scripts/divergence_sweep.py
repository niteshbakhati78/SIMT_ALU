"""
divergence_sweep.py — Extension 2: PDOM Divergence Experiment
==============================================================
Sweeps branch divergence probability across 0%–75% and measures:
  - IPC degradation vs baseline (0% divergence)
  - Masked thread-cycles overhead per divergence rate

The simulation binary receives:
  +divergence_rate=<float>  (0.0–1.0)  — fraction of branches that diverge
  +warp_count=<N>
  +mem_latency=<N>
  +stats_file=<path>

The divergence testbench (tb_divergence_phase4.sv) reads +divergence_rate
and probabilistically makes branches diverge or converge.

Usage:
  python scripts/divergence_sweep.py [--sim <cmd>] [--outdir <dir>]
"""

import subprocess
import json
import argparse
from pathlib import Path

try:
    import matplotlib.pyplot as plt
    import numpy as np
    HAS_MATPLOTLIB = True
except ImportError:
    HAS_MATPLOTLIB = False
    print("WARNING: matplotlib not installed — plots will be skipped.")

# ── Configuration ─────────────────────────────────────────────────────────────

DIVERGENCE_RATES = [0.0, 0.10, 0.25, 0.50, 0.75]
WARP_COUNT       = 16    # fixed: isolate divergence effect
MEM_LATENCY      = 50    # fixed: baseline memory latency

# Adjust to your simulator
SIM_CMD = ["vvp", "sim_divergence.vvp"]

# ── Stat Parsers ──────────────────────────────────────────────────────────────

def parse_div_stats(filepath: str, warp_count: int) -> dict:
    stats = {}
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if "=" in line:
                key, val = line.split("=", 1)
                stats[key] = int(val)

    cycles = stats.get("cycles", 1)
    instrs = stats.get("instructions", 0)
    mtc    = stats.get("masked_thread_cycles", 0)

    stats["ipc"] = instrs / cycles if cycles > 0 else 0.0
    # Divergence overhead = masked thread-cycles / (total thread-cycles)
    stats["divergence_overhead_pct"] = (
        mtc / (cycles * warp_count) * 100.0
    ) if cycles > 0 else 0.0
    return stats

# ── Sweep Runner ───────────────────────────────────────────────────────────────

def run_divergence_sweep(sim_cmd: list[str], output_dir: Path) -> dict:
    results = {}
    for rate in DIVERGENCE_RATES:
        pct = rate * 100
        print(f"  Divergence rate = {pct:4.0f}%  ", end="", flush=True)

        stats_path = output_dir / f"div_stats_{int(pct):03d}.txt"
        cmd = sim_cmd + [
            f"+divergence_rate={rate:.2f}",
            f"+warp_count={WARP_COUNT}",
            f"+mem_latency={MEM_LATENCY}",
            f"+stats_file={stats_path}",
        ]

        try:
            subprocess.run(cmd, check=True, capture_output=True, timeout=120)
            s = parse_div_stats(str(stats_path), WARP_COUNT)
            results[rate] = s
            print(f"IPC={s['ipc']:.3f}  DivOverhead={s['divergence_overhead_pct']:.1f}%")
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"FAILED: {e}")
            results[rate] = {"ipc": 0.0, "divergence_overhead_pct": 0.0}

    # Save
    serializable = {f"rate_{r:.2f}": v for r, v in results.items()}
    with open(output_dir / "divergence_raw.json", "w") as f:
        json.dump(serializable, f, indent=2)
    print(f"\n  Raw results saved to {output_dir / 'divergence_raw.json'}")

    return results

# ── Plots ──────────────────────────────────────────────────────────────────────

def plot_divergence_ipc(results: dict, output_dir: Path):
    rates    = sorted(results.keys())
    ipcs     = [results[r]["ipc"] for r in rates]
    base_ipc = ipcs[0] if ipcs[0] > 0 else 1.0

    degradation = [(base_ipc - ipc) / base_ipc * 100.0 for ipc in ipcs]

    fig, axes = plt.subplots(1, 2, figsize=(13, 5))

    # Left: IPC vs divergence rate
    axes[0].plot([r * 100 for r in rates], ipcs,
                 marker="o", color="#F44336", linewidth=2, markersize=8)
    axes[0].axhline(y=base_ipc, color="gray", linestyle="--",
                    alpha=0.6, label=f"Baseline IPC = {base_ipc:.3f}")
    axes[0].set_xlabel("Branch Divergence Rate (%)", fontsize=12)
    axes[0].set_ylabel("IPC", fontsize=12)
    axes[0].set_title("IPC Degradation vs Divergence Rate", fontsize=13)
    axes[0].set_xticks([r * 100 for r in rates])
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)
    axes[0].set_ylim(bottom=0)

    # Right: IPC degradation %
    bar_x = [r * 100 for r in rates]
    axes[1].bar(bar_x, degradation, color="#FF9800", edgecolor="black",
                width=8, alpha=0.85)
    for xi, di in zip(bar_x, degradation):
        axes[1].text(xi, di + 0.5, f"{di:.1f}%", ha="center", va="bottom", fontsize=10)
    axes[1].set_xlabel("Branch Divergence Rate (%)", fontsize=12)
    axes[1].set_ylabel("IPC Degradation (%)", fontsize=12)
    axes[1].set_title("IPC Degradation % vs Divergence Rate", fontsize=13)
    axes[1].set_xticks(bar_x)
    axes[1].set_ylim(0, max(degradation) * 1.2 + 5 if degradation else 80)
    axes[1].grid(True, alpha=0.3, axis="y")

    fig.suptitle(
        f"PDOM Divergence Impact — {WARP_COUNT} Warps, {MEM_LATENCY}-cycle Mem Latency",
        fontsize=14, fontweight="bold"
    )
    fig.tight_layout()

    out = output_dir / "divergence_ipc.png"
    fig.savefig(out, dpi=150)
    print(f"  Saved: {out}")
    plt.close(fig)

def plot_masked_thread_overhead(results: dict, output_dir: Path):
    rates   = sorted(results.keys())
    overhead = [results[r]["divergence_overhead_pct"] for r in rates]

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot([r * 100 for r in rates], overhead,
            marker="D", color="#9C27B0", linewidth=2, markersize=8)
    ax.fill_between([r * 100 for r in rates], overhead, alpha=0.15, color="#9C27B0")
    ax.set_xlabel("Branch Divergence Rate (%)", fontsize=12)
    ax.set_ylabel("Masked Thread-Cycles Overhead (%)", fontsize=12)
    ax.set_title("Thread Masking Overhead vs Divergence Rate", fontsize=13)
    ax.set_xticks([r * 100 for r in rates])
    ax.set_ylim(bottom=0)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()

    out = output_dir / "masked_thread_overhead.png"
    fig.savefig(out, dpi=150)
    print(f"  Saved: {out}")
    plt.close(fig)

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="PDOM divergence sweep (Extension 2)")
    parser.add_argument("--sim",    default=None,              help="Simulator command")
    parser.add_argument("--outdir", default="divergence_results", help="Output directory")
    args = parser.parse_args()

    sim_cmd    = args.sim.split() if args.sim else SIM_CMD
    output_dir = Path(args.outdir)
    output_dir.mkdir(exist_ok=True)

    print("=== PDOM Divergence Sweep (Extension 2) ===")
    print(f"  Divergence rates : {[f'{r*100:.0f}%' for r in DIVERGENCE_RATES]}")
    print(f"  Warp count       : {WARP_COUNT}  (fixed)")
    print(f"  Memory latency   : {MEM_LATENCY} cycles (fixed)")
    print(f"  Sim command      : {' '.join(sim_cmd)}")
    print(f"  Output dir       : {output_dir}")
    print()

    results = run_divergence_sweep(sim_cmd, output_dir)

    if HAS_MATPLOTLIB:
        print("\nGenerating plots...")
        plot_divergence_ipc(results, output_dir)
        plot_masked_thread_overhead(results, output_dir)
        print(f"\nAll plots saved to: {output_dir}/")
    else:
        print("\nSkipping plots (matplotlib not available).")
        print(f"Raw data saved to: {output_dir}/divergence_raw.json")

    # Print summary table
    rates = sorted(results.keys())
    base  = results[rates[0]]["ipc"] if results[rates[0]]["ipc"] > 0 else 1.0
    print("\n--- Divergence Summary Table ---")
    print(f"{'Rate':>6}  {'IPC':>6}  {'Degradation':>12}  {'Masked Overhead':>16}")
    for r in rates:
        ipc  = results[r]["ipc"]
        deg  = (base - ipc) / base * 100.0 if base > 0 else 0.0
        ovhd = results[r]["divergence_overhead_pct"]
        print(f"{r*100:5.0f}%  {ipc:6.3f}  {deg:11.1f}%  {ovhd:15.1f}%")

if __name__ == "__main__":
    main()
