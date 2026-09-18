#!/usr/bin/env bash
#
# Build and run the official riscv-tests rv32ui suite against the core.
#
# The test sources come from tests/riscv-tests (a submodule, unmodified).
# Only the environment that starts them and reports their result is ours --
# see tests/env/riscv_test.h for why.
#
# Usage:
#   ./scripts/run_riscv_tests.sh          run every test
#   ./scripts/run_riscv_tests.sh add      run only tests matching "add"

set -u

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

ISA_DIR="tests/riscv-tests/isa"
MACRO_DIR="$ISA_DIR/macros/scalar"
ENV_DIR="tests/env"
BUILD_DIR="tests/build"

#---------------------------------------------------------------------------
# Tests that need features this core does not implement yet.
#---------------------------------------------------------------------------
#   fence_i  Zifencei (self-modifying code). Not part of the RV32I base.
#   ma_data  Misaligned load/store data. The core detects misalignment and
#            refuses the access; this test expects it to either complete
#            the access or trap, and trapping needs Zicsr (Phase 6).
SKIP_TESTS="fence_i ma_data"

#---------------------------------------------------------------------------
# Tool discovery. Same approach as run_tests.sh: prefer PATH, then fall back
# to the usual install locations so a fresh machine works with no setup.
#---------------------------------------------------------------------------
find_tool() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    for dir in "/c/iverilog/bin" "/c/Program Files/iverilog/bin"; do
        if [ -x "$dir/$name.exe" ]; then echo "$dir/$name.exe"; return 0; fi
    done
    return 1
}

# The RISC-V toolchain ships under several prefixes depending on where it
# came from: riscv-none-elf- (xPack), riscv64-unknown-elf- (upstream and
# Debian/Ubuntu), riscv32-unknown-elf- (some distributions).
find_riscv() {
    local suffix="$1"
    local prefix dir
    for prefix in riscv-none-elf riscv64-unknown-elf riscv32-unknown-elf \
                  riscv64-elf riscv-none-embed; do
        if command -v "$prefix-$suffix" >/dev/null 2>&1; then
            command -v "$prefix-$suffix"
            return 0
        fi
        for dir in "$HOME/opt"/*/bin /c/opt/*/bin /opt/*/bin; do
            if [ -x "$dir/$prefix-$suffix.exe" ]; then
                echo "$dir/$prefix-$suffix.exe"; return 0
            fi
            if [ -x "$dir/$prefix-$suffix" ]; then
                echo "$dir/$prefix-$suffix"; return 0
            fi
        done
    done
    return 1
}

IVERILOG="$(find_tool iverilog)" || { echo "error: iverilog not found"; exit 127; }
VVP="$(find_tool vvp)"           || { echo "error: vvp not found"; exit 127; }

RVGCC="$(find_riscv gcc)" || {
    echo "error: no RISC-V GCC found."
    echo
    echo "  Ubuntu/Debian : sudo apt-get install gcc-riscv64-unknown-elf"
    echo "  macOS         : brew tap riscv/riscv && brew install riscv-tools"
    echo "  Windows       : unzip the xPack toolchain into ~/opt/"
    echo "                  https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases"
    exit 127
}
RVOBJCOPY="$(find_riscv objcopy)" || { echo "error: objcopy not found next to gcc"; exit 127; }

if [ ! -f "$ISA_DIR/rv32ui/add.S" ]; then
    echo "error: test sources missing. Run:"
    echo "  git submodule update --init --depth 1 tests/riscv-tests"
    exit 1
fi

FILTER="${1:-}"

echo "riscv gcc: $RVGCC"
echo "iverilog : $IVERILOG"
echo

mkdir -p "$BUILD_DIR" sim

#---------------------------------------------------------------------------
# Build the simulation once; every test reuses it.
#---------------------------------------------------------------------------
SIM="sim/riscv_tests.vvp"
if ! "$IVERILOG" -g2012 -Wall -I rtl -I tb -o "$SIM" \
        rtl/*.v tb/riscv_tests_tb.v > sim/riscv_tests_build.log 2>&1; then
    echo "simulation build failed:"
    sed 's/^/    /' sim/riscv_tests_build.log
    exit 1
fi

#---------------------------------------------------------------------------
# Build and run each test
#---------------------------------------------------------------------------
PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=""

for SRC in "$ISA_DIR"/rv32ui/*.S; do
    NAME="$(basename "$SRC" .S)"

    if [ -n "$FILTER" ] && [[ "$NAME" != *"$FILTER"* ]]; then
        continue
    fi

    case " $SKIP_TESTS " in
        *" $NAME "*)
            printf '[ SKIP ] %-10s  needs a feature not implemented yet\n' "$NAME"
            SKIPPED=$((SKIPPED + 1))
            continue
            ;;
    esac

    ELF="$BUILD_DIR/$NAME.elf"
    LOG="$BUILD_DIR/$NAME.log"

    # -nostdlib/-nostartfiles: the test provides its own _start.
    # -fno-pie: keep symbol references absolute, not GOT-relative.
    if ! "$RVGCC" -march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles \
            -fno-pie -no-pie -Wa,--no-warn \
            -T "$ENV_DIR/link.ld" \
            -I "$ENV_DIR" -I "$MACRO_DIR" -I "$ISA_DIR/rv32ui" \
            -o "$ELF" "$SRC" > "$LOG" 2>&1; then
        printf '[ BUILD ] %-10s\n' "$NAME"
        sed 's/^/    /' "$LOG"
        FAILED=$((FAILED + 1))
        FAILED_NAMES="$FAILED_NAMES $NAME(build)"
        continue
    fi

    # Split the ELF into the two memory images. Instructions and data live
    # in physically separate memories, so they cannot share one image.
    "$RVOBJCOPY" -O binary --only-section=.text "$ELF" "$BUILD_DIR/$NAME.text.bin" 2>>"$LOG"
    "$RVOBJCOPY" -O binary --remove-section=.text "$ELF" "$BUILD_DIR/$NAME.data.bin" 2>>"$LOG"

    # od -tx4 prints little-endian 32-bit words, which is exactly the word
    # order $readmemh expects.
    od -An -tx4 -v -w4 "$BUILD_DIR/$NAME.text.bin" | tr -d ' ' \
        | grep -v '^$' > "$BUILD_DIR/$NAME.imem.hex"
    od -An -tx4 -v -w4 "$BUILD_DIR/$NAME.data.bin" | tr -d ' ' \
        | grep -v '^$' > "$BUILD_DIR/$NAME.dmem.hex"

    "$VVP" "$SIM" \
        "+NAME=$NAME" \
        "+IMEM=$BUILD_DIR/$NAME.imem.hex" \
        "+DMEM=$BUILD_DIR/$NAME.dmem.hex" > "$LOG" 2>&1

    if grep -q "^RESULT: PASS" "$LOG"; then
        DETAIL="$(grep "$NAME:" "$LOG" | head -1 | sed "s/.*$NAME: //")"
        printf '[ PASS ] %-10s  %s\n' "$NAME" "$DETAIL"
        PASSED=$((PASSED + 1))
    else
        printf '[ FAIL ] %-10s\n' "$NAME"
        # The $readmemh "not enough words" warning is expected: a test
        # program is always smaller than the memory it is loaded into.
        grep -v -e "^RESULT:" -e "Not enough words in the file" "$LOG" | sed 's/^/    /' | head -6
        FAILED=$((FAILED + 1))
        FAILED_NAMES="$FAILED_NAMES $NAME"
    fi
done

TOTAL=$((PASSED + FAILED))

echo
echo "=================================================="
if [ "$FAILED" -eq 0 ]; then
    echo " riscv-tests rv32ui: $PASSED/$TOTAL PASSED  ($SKIPPED skipped)"
    echo "=================================================="
    exit 0
else
    echo " riscv-tests rv32ui: $FAILED of $TOTAL FAILED --$FAILED_NAMES"
    echo "=================================================="
    exit 1
fi
