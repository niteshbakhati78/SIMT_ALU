# run_all_phases.do — Runs every testbench in dependency order
# Run from project root:
#   vsim -c -do sim/run_all_phases.do

if {[file exists work]} { vdel -lib work -all }
vlib work

set VFLAGS "-sv -work work +incdir+rtl/pkg"

proc run_tb {srcs tb_top} {
    global VFLAGS
    puts "\n====  $tb_top  ===="
    foreach f $srcs { eval vlog $VFLAGS $f }
    vsim -c work.$tb_top
    run -all
    quit -sim
}

# ── Phase 1: SIMT ALU ────────────────────────────────────────────────────────
run_tb {
    rtl/core/simd_lane_alu.sv
    rtl/core/simt_alu_core.sv
    rtl/top/simt_alu.sv
    testbench/phase1/tb_simt_alu.sv
} simt_alu_tb

# ── Phase 3A: SIMT Stack ─────────────────────────────────────────────────────
run_tb {
    rtl/core/simt_stack.sv
    testbench/phase3/tb_simt_stack_phase3.sv
} tb_simt_stack_phase3

# ── Phase 3B: Branch Control ─────────────────────────────────────────────────
run_tb {
    rtl/core/simt_stack.sv
    rtl/top/simt_branch_control.sv
    testbench/phase3/tb_branch_control_phase3.sv
} tb_branch_control_phase3

# ── Phase 4: Mini-SM Integration ─────────────────────────────────────────────
set PHASE4_SRC {
    rtl/pkg/simt_alu_pkg.sv
    rtl/core/simd_lane_alu.sv
    rtl/core/simt_alu_core.sv
    rtl/top/simt_alu.sv
    rtl/core/simt_stack.sv
    rtl/top/simt_branch_control.sv
    rtl/control/warp_scheduler.sv
    rtl/control/wrap_table.sv
    rtl/control/scoreboard.sv
    rtl/core/exec_pipe.sv
    rtl/control/pdom_ctrl.sv
    rtl/top/mini_sm_top.sv
}

run_tb [concat $PHASE4_SRC {testbench/phase4/tb_mini_sm_phase4.sv}] \
    tb_mini_sm_phase4

# ── Extension 2: Divergence ──────────────────────────────────────────────────
run_tb [concat $PHASE4_SRC {testbench/phase4/tb_divergence_phase4.sv}] \
    tb_divergence_phase4

puts "\n========================================="
puts "All testbenches complete."
puts "========================================="
quit -f
