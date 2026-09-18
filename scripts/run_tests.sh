#!/usr/bin/env bash
#
# Build and run every self-checking testbench in tb/.
#
# Each testbench must print a final line of "RESULT: PASS" or "RESULT: FAIL".
# This script exits non-zero if any testbench fails, so CI catches it.
#
# Usage:
#   ./scripts/run_tests.sh            run every testbench
#   ./scripts/run_tests.sh alu        run only testbenches matching "alu"

set -u

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

#---------------------------------------------------------------------------
# Locate Icarus Verilog. Prefer PATH; fall back to the default Windows
# install location so a fresh Windows checkout works with no PATH setup.
#---------------------------------------------------------------------------
find_tool() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    for dir in "/c/iverilog/bin" "/c/Program Files/iverilog/bin"; do
        if [ -x "$dir/$name.exe" ]; then
            echo "$dir/$name.exe"
            return 0
        fi
    done
    return 1
}

IVERILOG="$(find_tool iverilog)" || {
    echo "error: iverilog not found."
    echo "  Linux : sudo apt-get install iverilog"
    echo "  macOS : brew install icarus-verilog"
    echo "  Windows: winget install --id Icarus.Verilog -e"
    exit 127
}
VVP="$(find_tool vvp)" || { echo "error: vvp not found next to iverilog"; exit 127; }

LINT_ONLY=0
if [ "${1:-}" = "--lint" ]; then
    LINT_ONLY=1
    shift
fi

FILTER="${1:-}"
mkdir -p sim

PASSED=0
FAILED=0
FAILED_NAMES=""

echo "iverilog: $IVERILOG"
echo

for TB in tb/tb_*.v; do
    [ -e "$TB" ] || { echo "no testbenches found in tb/"; exit 1; }
    NAME="$(basename "$TB" .v)"

    if [ -n "$FILTER" ] && [[ "$NAME" != *"$FILTER"* ]]; then
        continue
    fi

    OUT="sim/$NAME.vvp"
    LOG="sim/$NAME.log"

    # -g2012 enables Verilog-2005/SystemVerilog-lite constructs.
    # -Wall surfaces width mismatches and implicit nets early.
    if ! "$IVERILOG" -g2012 -Wall -I rtl -I tb -o "$OUT" rtl/*.v "$TB" > "$LOG" 2>&1; then
        echo "[ BUILD FAIL ] $NAME"
        sed 's/^/    /' "$LOG"
        FAILED=$((FAILED + 1))
        FAILED_NAMES="$FAILED_NAMES $NAME(build)"
        continue
    fi

    # Keep compile warnings visible even on a successful build.
    if [ -s "$LOG" ]; then
        sed 's/^/    warn: /' "$LOG"
    fi

    if [ "$LINT_ONLY" -eq 1 ]; then
        echo "[ LINT ] $NAME"
        PASSED=$((PASSED + 1))
        continue
    fi

    "$VVP" "$OUT" > "$LOG" 2>&1
    if grep -q "^RESULT: PASS" "$LOG"; then
        SUMMARY="$(grep '^--- ' "$LOG" | head -1 | sed 's/^--- //')"
        echo "[ PASS ] $NAME  ($SUMMARY)"
        PASSED=$((PASSED + 1))
    else
        echo "[ FAIL ] $NAME"
        sed 's/^/    /' "$LOG"
        FAILED=$((FAILED + 1))
        FAILED_NAMES="$FAILED_NAMES $NAME"
    fi
done

echo
echo "=================================================="
if [ "$FAILED" -eq 0 ]; then
    if [ "$LINT_ONLY" -eq 1 ]; then
        echo " LINT CLEAN  ($PASSED files elaborated, no warnings)"
    else
        echo " ALL TESTBENCHES PASSED  ($PASSED/$((PASSED + FAILED)))"
    fi
    echo "=================================================="
    exit 0
else
    echo " FAILURES: $FAILED of $((PASSED + FAILED))  --$FAILED_NAMES"
    echo "=================================================="
    exit 1
fi
