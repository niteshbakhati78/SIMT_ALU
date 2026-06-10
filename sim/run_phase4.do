# run_phase4.do — ModelSim do-file for Phase 4 Mini-SM + Extensions
# Run from project root:
#   vsim -c -do sim/run_phase4.do
# Or from ModelSim GUI: File > Do...

# Create/reset work library
if {[file exists work]} { vdel -lib work -all }
vlib work

# Common flags
set VFLAGS "-sv -work work +incdir+rtl/pkg"

# -----------------------------------------------------------------------
# Compile Phase 4 source (package must come first)
# -----------------------------------------------------------------------
eval vlog $VFLAGS \
    rtl/pkg/simt_alu_pkg.sv \
    rtl/core/simd_lane_alu.sv \
    rtl/core/simt_alu_core.sv \
    rtl/top/simt_alu.sv \
    rtl/core/simt_stack.sv \
    rtl/top/simt_branch_control.sv \
    rtl/control/warp_scheduler.sv \
    rtl/control/wrap_table.sv \
    rtl/control/scoreboard.sv \
    rtl/core/exec_pipe.sv \
    rtl/control/pdom_ctrl.sv \
    rtl/top/mini_sm_top.sv

# -----------------------------------------------------------------------
# Select which testbench to run (change tb_name to switch)
# -----------------------------------------------------------------------
#   tb_mini_sm_phase4    — Phase 4 RAW stall, latency hiding, fairness
#   tb_divergence_phase4 — Extension 2 PDOM divergence tests

set tb_name tb_mini_sm_phase4
# set tb_name tb_divergence_phase4

eval vlog $VFLAGS testbench/phase4/${tb_name}.sv

# -----------------------------------------------------------------------
# Simulate
# -----------------------------------------------------------------------
vsim -c work.$tb_name
run -all
quit -f
