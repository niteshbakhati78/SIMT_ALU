# =============================================================================
# SIMT ALU / Mini-SM Project — ModelSim ASE Makefile
# =============================================================================
# Usage:
#   make phase1        — run Phase 1 SIMT ALU testbench
#   make phase2        — run Phase 2 predicate mask testbench
#   make phase2_5      — run Phase 2.5 exec-mask-update testbench
#   make phase3_stack  — run Phase 3A SIMT stack testbench
#   make phase3_branch — run Phase 3B branch control testbench
#   make phase4        — run Phase 4 Mini-SM integration testbench
#   make divergence    — run Extension 2 PDOM divergence testbench
#   make all           — run every testbench in sequence
#   make clean         — remove ModelSim work library and logs
#
# Requires ModelSim ASE (vsim) on PATH.
# Set MODELSIM_PATH if vsim is not on your PATH, e.g.:
#   make MODELSIM_PATH="C:/intelFPGA/20.1/modelsim_ase/win32aloem" phase4
# =============================================================================

MODELSIM_PATH ?= C:/intelFPGA/20.1/modelsim_ase/win32aloem
VLOG          := $(MODELSIM_PATH)/vlog.exe
VSIM          := $(MODELSIM_PATH)/vsim.exe

# Common vlog flags
VLOG_FLAGS := -sv -work work +incdir+rtl/pkg

# Run flags: -c = batch (no GUI), -do "run -all; quit -f" = run then exit
VSIM_FLAGS := -c -do "run -all; quit -f"

# Source groups ---------------------------------------------------------------

PKG_SRC := rtl/pkg/simt_alu_pkg.sv

BASIC_SRC := \
    rtl/basic/full_adder.sv \
    rtl/basic/mux2.sv \
    rtl/basic/comparator.sv

ALU_SRC := \
    rtl/core/simd_lane_alu.sv \
    rtl/core/simt_alu_core.sv \
    rtl/top/simt_alu.sv

MASK_SRC := \
    rtl/core/predicate_mask_unit.sv \
    rtl/top/predicate_mask.sv

STACK_SRC := \
    rtl/core/simt_stack.sv \
    rtl/top/simt_branch_control.sv

CONTROL_SRC := \
    rtl/control/warp_scheduler.sv \
    rtl/control/wrap_table.sv \
    rtl/control/scoreboard.sv \
    rtl/core/exec_pipe.sv \
    rtl/control/pdom_ctrl.sv

TOP_SRC := rtl/top/mini_sm_top.sv

# Phase 4 + Extensions: full compile list (order matters)
PHASE4_SRC := \
    $(PKG_SRC) \
    $(ALU_SRC) \
    $(STACK_SRC) \
    $(CONTROL_SRC) \
    $(TOP_SRC)

# =============================================================================
# Targets
# =============================================================================

.PHONY: all phase1 phase2 phase2_5 phase3_stack phase3_branch \
        phase4 divergence clean work

all: phase1 phase2 phase3_stack phase3_branch phase4 divergence

# Create ModelSim work library ------------------------------------------------
work:
	@echo "Creating ModelSim work library..."
	$(MODELSIM_PATH)/vlib.exe work

# Phase 1: SIMT ALU (random + self-checking) ----------------------------------
phase1: work
	@echo "=== Phase 1: SIMT ALU ==="
	$(VLOG) $(VLOG_FLAGS) \
	    $(ALU_SRC) \
	    testbench/phase1/tb_simt_alu.sv
	$(VSIM) $(VSIM_FLAGS) simt_alu_tb
	@echo ""

# Phase 2: Predicate Mask Unit ------------------------------------------------
phase2: work
	@echo "=== Phase 2: Predicate Mask ==="
	$(VLOG) $(VLOG_FLAGS) \
	    $(MASK_SRC) \
	    testbench/phase2/tb_predicate_mask_phase2.sv
	$(VSIM) $(VSIM_FLAGS) tb_predicate_mask_phase2
	@echo ""

# Phase 2.5: Exec Mask Update -------------------------------------------------
phase2_5: work
	@echo "=== Phase 2.5: Exec Mask Update ==="
	$(VLOG) $(VLOG_FLAGS) \
	    $(ALU_SRC) \
	    $(MASK_SRC) \
	    rtl/top/simt_exec_mask_update.sv \
	    testbench/phase2.5/tb_exec_mask_update.sv
	$(VSIM) $(VSIM_FLAGS) tb_exec_mask_update
	@echo ""

# Phase 3A: SIMT Stack --------------------------------------------------------
phase3_stack: work
	@echo "=== Phase 3A: SIMT Stack ==="
	$(VLOG) $(VLOG_FLAGS) \
	    rtl/core/simt_stack.sv \
	    testbench/phase3/tb_simt_stack_phase3.sv
	$(VSIM) $(VSIM_FLAGS) tb_simt_stack_phase3
	@echo ""

# Phase 3B: Branch Control ----------------------------------------------------
phase3_branch: work
	@echo "=== Phase 3B: Branch Control ==="
	$(VLOG) $(VLOG_FLAGS) \
	    rtl/core/simt_stack.sv \
	    rtl/top/simt_branch_control.sv \
	    testbench/phase3/tb_branch_control_phase3.sv
	$(VSIM) $(VSIM_FLAGS) tb_branch_control_phase3
	@echo ""

# Phase 4: Mini-SM Integration ------------------------------------------------
phase4: work
	@echo "=== Phase 4: Mini-SM Integration ==="
	$(VLOG) $(VLOG_FLAGS) \
	    $(PHASE4_SRC) \
	    testbench/phase4/tb_mini_sm_phase4.sv
	$(VSIM) $(VSIM_FLAGS) tb_mini_sm_phase4
	@echo ""

# Extension 2: Divergence Testbench -------------------------------------------
divergence: work
	@echo "=== Extension 2: PDOM Divergence ==="
	$(VLOG) $(VLOG_FLAGS) \
	    $(PHASE4_SRC) \
	    testbench/phase4/tb_divergence_phase4.sv
	$(VSIM) $(VSIM_FLAGS) tb_divergence_phase4
	@echo ""

# C++ Functional Model --------------------------------------------------------
# Requires GCC 14+ (MSYS2 ucrt64): add C:\msys64\ucrt64\bin to PATH first.
# Usage: make cpp_tests
CPP       := g++
CPP_FLAGS := -std=c++17 -Wall -O2 -Iinclude
CPP_SRCS  := src/simt_types.cpp src/scoreboard.cpp src/warp_table.cpp \
             src/warp_scheduler.cpp src/exec_pipe.cpp src/mini_sm.cpp

cpp_tests: sim/build/test_scoreboard.exe sim/build/test_warp_table.exe sim/build/test_mini_sm.exe
	sim/build/test_scoreboard.exe
	sim/build/test_warp_table.exe
	sim/build/test_mini_sm.exe

sim/build/test_scoreboard.exe:
	mkdir -p sim/build
	$(CPP) $(CPP_FLAGS) -Isim/include $(CPP_SRCS:%=sim/%) sim/tests/test_scoreboard.cpp -o $@

sim/build/test_warp_table.exe:
	mkdir -p sim/build
	$(CPP) $(CPP_FLAGS) -Isim/include $(CPP_SRCS:%=sim/%) sim/tests/test_warp_table.cpp -o $@

sim/build/test_mini_sm.exe:
	mkdir -p sim/build
	$(CPP) $(CPP_FLAGS) -Isim/include $(CPP_SRCS:%=sim/%) sim/tests/test_mini_sm.cpp -o $@

# Clean -----------------------------------------------------------------------
clean:
	@echo "Cleaning build artifacts..."
	$(MODELSIM_PATH)/vdel.exe -lib work -all 2>nul || true
	-rm -f transcript vsim.wlf modelsim.ini sim_stats.txt div_stats.txt
	-rm -rf sim/build
	@echo "Clean done."
