#!/usr/bin/env bash
#
# Run the Vivado build. Finds Vivado the same way the other runners find
# their tools: PATH first, then the usual install locations, because the
# installer does not add itself to PATH.
#
# Usage:
#   ./scripts/run_synth.sh

set -u

cd "$(dirname "$0")/.."

find_vivado() {
    if command -v vivado >/dev/null 2>&1; then
        command -v vivado
        return 0
    fi
    # 2025.2 installs under C:\AMDDesignTools; older releases used C:\Xilinx.
    # Newest version first, so a machine with several picks the latest.
    local root ver
    for root in /c/AMDDesignTools /c/Xilinx "/c/Program Files/Xilinx" \
                /d/AMDDesignTools /d/Xilinx; do
        [ -d "$root" ] || continue
        for ver in $(ls -1r "$root" 2>/dev/null); do
            if [ -x "$root/$ver/Vivado/bin/vivado.bat" ]; then
                echo "$root/$ver/Vivado/bin/vivado.bat"; return 0
            fi
            if [ -x "$root/Vivado/$ver/bin/vivado.bat" ]; then
                echo "$root/Vivado/$ver/bin/vivado.bat"; return 0
            fi
        done
    done
    return 1
}

VIVADO="$(find_vivado)" || {
    echo "error: Vivado not found."
    echo
    echo "  Expected somewhere like:"
    echo "    C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat"
    echo "    C:/Xilinx/Vivado/<version>/bin/vivado.bat"
    echo
    echo "  Install Vivado ML Standard (free, no licence) from"
    echo "  https://www.amd.com/en/support/downloads/adaptive-socs-and-fpgas/development-tools/"
    echo "  selecting Artix-7 only, or put vivado on PATH."
    exit 127
}

echo "vivado: $VIVADO"
echo

# -nojournal/-nolog: Vivado otherwise drops vivado.jou and vivado.log in the
# working directory on every run. The reports this build cares about are
# written explicitly by the script.
exec "$VIVADO" -mode batch -source scripts/build.tcl -nojournal -nolog
