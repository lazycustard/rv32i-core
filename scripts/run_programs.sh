#!/usr/bin/env bash
#
# Compile the C programs in tests/programs/, run each on the core, and
# compare what it printed against the matching .expected file.
#
# Usage:
#   ./scripts/run_programs.sh           run every program
#   ./scripts/run_programs.sh hello     run only programs matching "hello"

set -u

cd "$(dirname "$0")/.."

ENV_DIR="tests/env"
PROG_DIR="tests/programs"
BUILD_DIR="tests/build"

#---------------------------------------------------------------------------
# Tool discovery, same approach as the other runners.
#---------------------------------------------------------------------------
find_tool() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"; return 0
    fi
    for dir in "/c/iverilog/bin" "/c/Program Files/iverilog/bin"; do
        if [ -x "$dir/$name.exe" ]; then echo "$dir/$name.exe"; return 0; fi
    done
    return 1
}

find_riscv() {
    local suffix="$1"
    local prefix dir
    for prefix in riscv-none-elf riscv64-unknown-elf riscv32-unknown-elf \
                  riscv64-elf riscv-none-embed; do
        if command -v "$prefix-$suffix" >/dev/null 2>&1; then
            command -v "$prefix-$suffix"; return 0
        fi
        for dir in "$HOME/opt"/*/bin /c/opt/*/bin /opt/*/bin; do
            [ -x "$dir/$prefix-$suffix.exe" ] && { echo "$dir/$prefix-$suffix.exe"; return 0; }
            [ -x "$dir/$prefix-$suffix" ]     && { echo "$dir/$prefix-$suffix";     return 0; }
        done
    done
    return 1
}

IVERILOG="$(find_tool iverilog)" || { echo "error: iverilog not found"; exit 127; }
VVP="$(find_tool vvp)"           || { echo "error: vvp not found"; exit 127; }
RVGCC="$(find_riscv gcc)" || {
    echo "error: no RISC-V GCC found."
    echo "  Ubuntu/Debian : sudo apt-get install gcc-riscv64-unknown-elf"
    echo "  Windows       : unzip the xPack toolchain into ~/opt/"
    exit 127
}
RVOBJCOPY="$(find_riscv objcopy)" || { echo "error: objcopy not found"; exit 127; }

FILTER="${1:-}"

echo "riscv gcc: $RVGCC"
echo

mkdir -p "$BUILD_DIR" sim

#---------------------------------------------------------------------------
# One simulation binary, reused by every program.
#---------------------------------------------------------------------------
SIM="sim/program.vvp"
if ! "$IVERILOG" -g2012 -Wall -I rtl -I tb -o "$SIM" \
        rtl/*.v tb/program_tb.v > sim/program_build.log 2>&1; then
    echo "simulation build failed:"
    sed 's/^/    /' sim/program_build.log
    exit 1
fi

PASSED=0
FAILED=0
FAILED_NAMES=""

for SRC in "$PROG_DIR"/*.c; do
    [ -e "$SRC" ] || { echo "no programs in $PROG_DIR"; exit 1; }
    NAME="$(basename "$SRC" .c)"

    if [ -n "$FILTER" ] && [[ "$NAME" != *"$FILTER"* ]]; then
        continue
    fi

    ELF="$BUILD_DIR/$NAME.elf"
    LOG="$BUILD_DIR/$NAME.log"
    OUT="$BUILD_DIR/$NAME.out"
    EXPECTED="$PROG_DIR/$NAME.expected"

    # -ffreestanding/-fno-builtin: there is no C library, so the compiler
    #   must not assume one exists or rewrite loops into calls to it.
    # -lgcc: RV32I has no divide instruction, so integer division becomes a
    #   call to __udivsi3, which lives in libgcc.
    if ! "$RVGCC" -march=rv32i -mabi=ilp32 -O2 \
            -static -nostdlib -nostartfiles -ffreestanding -fno-builtin \
            -Wall -Wextra \
            -T "$ENV_DIR/link_c.ld" -I "$ENV_DIR" \
            -o "$ELF" "$ENV_DIR/crt0.S" "$SRC" -lgcc > "$LOG" 2>&1; then
        printf '[ BUILD ] %-12s\n' "$NAME"
        sed 's/^/    /' "$LOG"
        FAILED=$((FAILED + 1))
        FAILED_NAMES="$FAILED_NAMES $NAME(build)"
        continue
    fi

    # Split into the two memory images: instructions and data live in
    # physically separate memories.
    "$RVOBJCOPY" -O binary --only-section=.text "$ELF" "$BUILD_DIR/$NAME.text.bin" 2>>"$LOG"
    "$RVOBJCOPY" -O binary --remove-section=.text "$ELF" "$BUILD_DIR/$NAME.data.bin" 2>>"$LOG"

    od -An -tx4 -v -w4 "$BUILD_DIR/$NAME.text.bin" | tr -d ' ' \
        | grep -v '^$' > "$BUILD_DIR/$NAME.imem.hex"
    od -An -tx4 -v -w4 "$BUILD_DIR/$NAME.data.bin" | tr -d ' ' \
        | grep -v '^$' > "$BUILD_DIR/$NAME.dmem.hex"

    "$VVP" "$SIM" \
        "+NAME=$NAME" \
        "+IMEM=$BUILD_DIR/$NAME.imem.hex" \
        "+DMEM=$BUILD_DIR/$NAME.dmem.hex" \
        "+OUT=$OUT" > "$LOG" 2>&1

    if ! grep -q "^RESULT: PASS" "$LOG"; then
        printf '[ FAIL ] %-12s  did not finish cleanly\n' "$NAME"
        grep -v -e "^RESULT:" -e "Not enough words in the file" "$LOG" \
            | sed 's/^/    /' | tail -4
        FAILED=$((FAILED + 1))
        FAILED_NAMES="$FAILED_NAMES $NAME"
        continue
    fi

    if [ ! -f "$EXPECTED" ]; then
        printf '[ FAIL ] %-12s  no %s to compare against\n' "$NAME" "$EXPECTED"
        FAILED=$((FAILED + 1))
        FAILED_NAMES="$FAILED_NAMES $NAME(no-expected)"
        continue
    fi

    if diff -u "$EXPECTED" "$OUT" > "$BUILD_DIR/$NAME.diff" 2>&1; then
        STATS="$(grep "^STATS: " "$LOG" | head -1 | sed "s/^STATS: //")"
        printf '[ PASS ] %-12s  %s\n' "$NAME" "$STATS"
        # When one program was asked for, show what it actually printed.
        if [ -n "$FILTER" ]; then
            sed 's/^/           | /' "$OUT"
        fi
        PASSED=$((PASSED + 1))
    else
        printf '[ FAIL ] %-12s  output does not match\n' "$NAME"
        sed 's/^/    /' "$BUILD_DIR/$NAME.diff" | head -12
        FAILED=$((FAILED + 1))
        FAILED_NAMES="$FAILED_NAMES $NAME"
    fi
done

TOTAL=$((PASSED + FAILED))

echo
echo "=================================================="
if [ "$FAILED" -eq 0 ]; then
    echo " programs: $PASSED/$TOTAL PASSED"
    echo "=================================================="
    exit 0
else
    echo " programs: $FAILED of $TOTAL FAILED --$FAILED_NAMES"
    echo "=================================================="
    exit 1
fi
