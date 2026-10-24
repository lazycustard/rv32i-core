#=========================================================================
# build.tcl - Non-project Vivado build for rv32i-core
#
# Run with:
#     vivado -mode batch -source scripts/build.tcl
#
# Non-project mode on purpose. A Vivado project is a .xpr plus a tree of
# generated directories -- binary, machine-specific, and useless in version
# control. This script is the build: it is readable, it is diffable, and it
# produces the same result on any machine with the same Vivado.
#
# It answers three questions simulation cannot:
#   - how much of the chip does the core take (utilisation)
#   - how fast can it run (Fmax, derived from timing slack)
#   - what is holding it back (the critical path)
#
# Nothing here needs a board. Synthesis, placement, routing and timing
# analysis all run against a model of the device.
#=========================================================================

set part      "xc7a35tcpg236-1"    ;# Artix-7 35T, the Basys 3 part
set top       "rv32i_core"
set period_ns 10.000               ;# must match constraints/core.xdc

# The top is rv32i_core, the pipeline on its own, with the memories outside
# it. That is not a convenience: with the memories inside, the program was a
# compile-time constant and synthesis folded the whole design down to three
# LUTs. rv32i_soc wires the memories back on for simulation.

# The repository root, passed in by run_synth.sh. Vivado itself runs from a
# scratch directory outside OneDrive, so every path here has to be absolute.
if {[llength $argv] < 1} {
    puts "ERROR: no repository root given. Run via scripts/run_synth.sh."
    exit 1
}
set repo [lindex $argv 0]

# Outputs go to Vivado's own working directory -- the scratch dir outside
# OneDrive -- not straight into the repository. OneDrive takes transient
# locks on folders it is syncing, and Vivado reports that as
#   ERROR: the path .../build ... is not writable
# even when the shell can write there perfectly well. run_synth.sh copies
# the reports back afterwards; the checkpoints are large and git-ignored,
# so they stay in the scratch directory.
set outdir "build"
set rptdir "reports"
file mkdir $outdir
file mkdir $rptdir

puts "=========================================================="
puts " rv32i-core  |  part $part  |  target [expr {1000.0/$period_ns}] MHz"
puts "=========================================================="

#-------------------------------------------------------------------------
# Read design
#-------------------------------------------------------------------------
read_verilog [glob $repo/rtl/*.v]
read_xdc $repo/constraints/core.xdc

#-------------------------------------------------------------------------
# Synthesis
#-------------------------------------------------------------------------
# out_of_context: no I/O buffers are inserted, so the core can be analysed
# without inventing pin assignments for a board it is not on.
synth_design -top $top -part $part -mode out_of_context

write_checkpoint -force $outdir/post_synth.dcp
report_utilization -file $rptdir/post_synth_utilization.rpt

#-------------------------------------------------------------------------
# Implementation
#-------------------------------------------------------------------------
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force $outdir/post_route.dcp

report_utilization       -file $rptdir/utilization.rpt
report_timing_summary    -file $rptdir/timing_summary.rpt
report_power             -file $rptdir/power.rpt

# The ten worst paths, with full logic detail. This is where a slow design
# is diagnosed: the report names the cells the critical path runs through.
report_timing -sort_by group -max_paths 10 -path_type full \
    -file $rptdir/critical_paths.rpt

#-------------------------------------------------------------------------
# Pull the headline numbers out, so they do not have to be dug for.
#
# Everything below is wrapped in catch. Synthesis and implementation take
# minutes; a typo in a reporting query must not throw that away. The
# checkpoint and the full reports are already written by this point, so a
# failure here loses only the convenience summary -- reopen post_route.dcp
# and query it directly.
#-------------------------------------------------------------------------
proc count_prims {group} {
    if {[catch {
        set n [llength [get_cells -hierarchical -quiet \
                   -filter "PRIMITIVE_GROUP == $group"]]
    } err]} {
        puts "  (could not count $group: $err)"
        return -1
    }
    return $n
}

set wns  "unknown"
set fmax "unknown"
if {[catch {
    set paths [get_timing_paths -max_paths 1 -nworst 1 -delay_type max]
    set wns   [get_property SLACK [lindex $paths 0]]
    set fmax  [expr {1000.0 / ($period_ns - $wns)}]
} err]} {
    puts "  (could not read timing slack: $err)"
    puts "  Read it from $rptdir/timing_summary.rpt instead."
}

set luts  [count_prims LUT]
set ffs   [count_prims FLOP_LATCH]
set brams [count_prims BLOCKRAM]
set dsps  [count_prims ARITHMETIC]

puts ""
puts "=========================================================="
puts " RESULTS"
puts "=========================================================="
puts [format " LUTs            %8s" $luts]
puts [format " Flip-flops      %8s" $ffs]
puts [format " Block RAMs      %8s" $brams]
puts [format " DSP slices      %8s" $dsps]
puts ""
if {$wns ne "unknown"} {
    puts [format " Worst slack     %8.3f ns  (target %.1f ns)" $wns $period_ns]
    puts [format " Fmax            %8.1f MHz" $fmax]
    puts ""
    if {$wns < 0} {
        puts " Timing NOT met at the target period. Fmax above is still the"
        puts " achievable frequency; the target was simply set too high."
    } else {
        puts " Timing met. Fmax above is what the critical path allows, so"
        puts " tightening the target would not change it."
    }
}
puts "=========================================================="
puts " Reports in $rptdir/ -- critical_paths.rpt names the cells on the"
puts " path that sets Fmax. Checkpoint in $outdir/post_route.dcp."
puts "=========================================================="

# Write the headline numbers where a script can read them back.
catch {
    set fh [open "$rptdir/summary.txt" w]
    puts $fh "part      $part"
    puts $fh "luts      $luts"
    puts $fh "ffs       $ffs"
    puts $fh "brams     $brams"
    puts $fh "dsps      $dsps"
    puts $fh "wns_ns    $wns"
    puts $fh "fmax_mhz  $fmax"
    puts $fh "top       $top"
    close $fh
}
