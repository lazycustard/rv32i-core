#!/usr/bin/env bash
#
# Run the Vivado build. Finds Vivado the same way the other runners find
# their tools: PATH first, then the usual install locations, because the
# installer does not add itself to PATH.
#
# Usage:
#   ./scripts/run_synth.sh              default placement
#   PBLOCK=1 ./scripts/run_synth.sh     confine the design to one clock region

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
            # -f not -x: a .bat carries no executable bit under Git Bash.
            if [ -f "$root/$ver/Vivado/bin/vivado.bat" ]; then
                echo "$root/$ver/Vivado/bin/vivado.bat"; return 0
            fi
            if [ -f "$root/Vivado/$ver/bin/vivado.bat" ]; then
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

REPO="$(pwd)"

# Vivado creates a .Xil scratch directory in whatever its working directory
# is, and deletes it on exit. This repository lives under OneDrive, which
# holds file handles open while it syncs, so that delete fails and takes
# synth_design down with it:
#
#   ERROR: [Designutils 20-411] The directory '.../.Xil/.../realtime'
#   could not be deleted and may be locked.
#
# So Vivado is run from a scratch directory outside any synced folder, and
# told where the repository is. Sources are read from there and reports are
# written back there; only Vivado's own temporary files stay behind.
SCRATCH="${TEMP:-/tmp}/rv32i-core-synth"
mkdir -p "$SCRATCH"

echo "vivado:  $VIVADO"
echo "repo:    $REPO"
echo "scratch: $SCRATCH"
echo

cd "$SCRATCH"

# -nojournal/-nolog: Vivado otherwise drops vivado.jou and vivado.log in the
# working directory on every run. The reports this build cares about are
# written explicitly by the script.
"$VIVADO" -mode batch -source "$REPO/scripts/build.tcl" \
    -nojournal -nolog -tclargs "$REPO" "${PBLOCK:-0}"
rc=$?

# Bring the reports back into the repository. They are small text files and
# are the point of the whole run; the .dcp checkpoints are large and
# git-ignored, so they stay behind in the scratch directory.
if [ -d "$SCRATCH/reports" ]; then
    mkdir -p "$REPO/reports"
    cp -f "$SCRATCH/reports/"* "$REPO/reports/" 2>/dev/null
    echo
    echo "reports copied to $REPO/reports/"
fi

exit $rc
