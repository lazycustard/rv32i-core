#!/usr/bin/env bash
#
# Open the routed design in the Vivado GUI, to look at what the build
# produced rather than only read numbers about it.
#
# Worth opening:
#   Device        the Artix-7 floorplan, with the core's logic placed on it
#   Schematic     the synthesised netlist, zoomable down to individual gates
#   Timing        Reports > Timing > the critical path, highlighted on the chip
#
# Usage:
#   ./scripts/open_gui.sh
#
# The build itself stays in batch mode. A GUI build is a sequence of clicks
# that nobody else can repeat; this is just a viewer for the result.

set -u

cd "$(dirname "$0")/.."
REPO="$(pwd)"

find_vivado() {
    if command -v vivado >/dev/null 2>&1; then
        command -v vivado; return 0
    fi
    local root ver
    for root in /c/AMDDesignTools /c/Xilinx "/c/Program Files/Xilinx" \
                /d/AMDDesignTools /d/Xilinx; do
        [ -d "$root" ] || continue
        for ver in $(ls -1r "$root" 2>/dev/null); do
            [ -f "$root/$ver/Vivado/bin/vivado.bat" ] && \
                { echo "$root/$ver/Vivado/bin/vivado.bat"; return 0; }
            [ -f "$root/Vivado/$ver/bin/vivado.bat" ] && \
                { echo "$root/Vivado/$ver/bin/vivado.bat"; return 0; }
        done
    done
    return 1
}

VIVADO="$(find_vivado)" || { echo "error: Vivado not found."; exit 127; }

# The checkpoint stays in the scratch directory, because writing it into a
# OneDrive-synced folder is what broke the build in the first place.
SCRATCH="${TEMP:-/tmp}/rv32i-core-synth"
DCP="$SCRATCH/build/post_route.dcp"

if [ ! -f "$DCP" ]; then
    echo "error: no routed checkpoint at"
    echo "  $DCP"
    echo
    echo "Run 'make synth' first."
    exit 1
fi

echo "opening $DCP"
echo "(Vivado takes a little while to start, and keeps this terminal busy)"

# A one-line Tcl script rather than a heredoc: Vivado reads its commands
# from -source, not from stdin.
OPEN_TCL="$SCRATCH/open_checkpoint.tcl"
printf 'open_checkpoint {%s}\n' "$DCP" > "$OPEN_TCL"

cd "$SCRATCH"
exec "$VIVADO" -mode gui -source "$OPEN_TCL" -nojournal -nolog
