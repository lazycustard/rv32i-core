#=========================================================================
# core.xdc - Timing constraints for out-of-context synthesis
#
# The core is synthesised on its own, not wired to a board, so there are no
# pin assignments here -- only a clock. That is deliberate: the question
# being asked is how fast the logic itself can run and how much of the chip
# it takes, and neither answer depends on which physical pins it would use.
#
# The period below is a target, not a measurement. Timing analysis reports
# the slack against it, and the achievable frequency is derived from that:
#
#     Fmax = 1000 / (period_ns - slack_ns)
#
# So a tight target that fails timing and a loose one that passes give the
# same Fmax, as long as the tool is not given so much slack that it stops
# optimising. 10 ns (100 MHz) is a reasonable starting point for a small
# core on Artix-7.
#=========================================================================

create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk_i]

# Reset is asserted for many cycles by whatever drives it and is not on a
# critical path worth analysing.
set_false_path -from [get_ports rst_i]
