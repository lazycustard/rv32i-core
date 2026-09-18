#===========================================================================
# RV32I core - build and test
#
#   make            run every self-checking testbench
#   make test       same
#   make test TB=alu    run only testbenches matching "alu"
#   make wave TB=alu    open the waveform for one testbench in GTKWave
#   make lint       syntax + width check, no simulation
#   make riscv-tests    official riscv-tests suite (needs RISC-V GCC)
#   make clean      remove build products
#
# Everything is delegated to scripts/run_tests.sh so that there is exactly
# one definition of how tests run. Windows users without GNU Make can call
# that script directly from Git Bash.
#===========================================================================

SHELL   := /bin/sh
RTL     := $(wildcard rtl/*.v)
TB_DIR  := tb
SIM_DIR := sim
TB      ?=

.PHONY: all test riscv-tests lint wave clean

all: test

test:
	@bash scripts/run_tests.sh $(TB)

# Elaborate every testbench without running it. Catches syntax errors,
# width mismatches and undeclared nets fast.
lint:
	@bash scripts/run_tests.sh --lint

wave:
	@test -n "$(TB)" || { echo "usage: make wave TB=alu"; exit 1; }
	@test -f $(SIM_DIR)/tb_$(TB).vcd || { echo "no waveform: run 'make test TB=$(TB)' first"; exit 1; }
	gtkwave $(SIM_DIR)/tb_$(TB).vcd

clean:
	@rm -rf $(SIM_DIR) tests/build
	@echo "cleaned"

# Official riscv-tests conformance suite. Needs a RISC-V GCC toolchain;
# see scripts/run_riscv_tests.sh for install hints.
riscv-tests:
	@bash scripts/run_riscv_tests.sh $(TB)
