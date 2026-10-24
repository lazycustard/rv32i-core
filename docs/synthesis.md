# Synthesis

What the core costs on a real FPGA, what limits its clock, and two
optimisations that did not work. See the [README](../README.md) for the
summary.


Simulation says whether the core is correct. It says nothing about how much
of a chip it takes or how fast it can run. For that it has to go through
Vivado — no board required; synthesis, placement, routing and timing
analysis all run against a model of the device.

```bash
make synth      # needs Vivado on PATH or in C:/AMDDesignTools, C:/Xilinx
make gui        # open the routed design to look at it
```

Artix-7 `xc7a35tcpg236-1`, out of context, `rv32i_core` alone:

| | | of device |
|---|---|---|
| LUTs | 1,642 | 7.9% |
| Flip-flops | 998 | 2.4% |
| LUT as memory | 164 | 1.7% |
| Block RAMs | 0 | — |
| DSPs | 0 | — |
| **Fmax** | **95.6 MHz** | WNS −0.458 ns against a 10 ns target |

The build is `scripts/build.tcl`, run in non-project mode. A Vivado project
is a `.xpr` and a tree of generated directories — binary, machine-specific,
and useless in version control. The script *is* the build.

## What synthesis caught that simulation could not

The first run reported **3 LUTs and 273 MHz**. That was not a bad design;
it was no design. With the memories inside `rv32i_core`, the program was a
compile-time constant — `imem` is filled with NOP by an initial block and
nothing outside could change it — so Vivado propagated that through the
whole pipeline. Only the free-running performance counters survived.

It was a real limitation, not just a measurement artefact: **a core with
its program sealed inside has no way to be given one on hardware.** The
testbenches reached in and wrote the memory arrays directly, which works in
simulation and nowhere else. 432 local checks, 40 official tests and 4 C
programs all passed over it. Synthesis found it on the first run.

So `rv32i_core` is now the pipeline alone, with memory reached through
ports, and `rv32i_soc` wires the memories on for simulation — which is also
the shape Phase 5 needs to swap them for block RAM.

## The critical path

```
ex_rs1_addr → hazard unit comparator → forwarding mux
            → branch comparator → mispredict → id_pc reset pin
```

17 logic levels, 9 of them carry chains, and **60% of the delay is routing
rather than logic** — the design is spread out more than it is deep.

## Two optimisations that did not work

Both are recorded because the reasoning is worth more than the outcome, and
because knowing what has already been tried is the useful part.

**Confining the design to one clock region.** The placer spread the logic
across two clock regions with a visible gap between the halves, and 60% of
the critical path was routing rather than logic. Packing everything into
`CLOCKREGION_X0Y1` with a pblock should shorten the wires.

It went the other way — **95.6 MHz → 91.1 MHz**. The interesting part is
how:

| | Logic | Routing | Levels |
|---|---|---|---|
| Default placement | 3.95 ns (40%) | 5.99 ns (60%) | 17 |
| Confined to one region | 2.39 ns (23%) | **7.98 ns (77%)** | 11 |

Logic delay fell and routing delay rose by a third, with every cell packed
into a *smaller* area. Shorter straight-line distances, longer wires: the
most likely reading is congestion — too much logic for the routing
resources of one region, so wires detour instead of going direct.

The gap was not waste. It was the placer relieving congestion, and
overriding it reintroduced exactly the problem it had been avoiding. Try
`PBLOCK=1 make synth` to reproduce; the default is off.

**Not clearing `id_pc` on flush.**

The path ends at a flip-flop *reset* pin, and `id_pc` is cleared on flush
for no reason: a flushed slot carries a NOP, which never reads it. Removing
that clear takes 64 reset pins off the end of the critical path.

It made things worse — **95.6 MHz → 93.8 MHz**. The path did not disappear,
it relocated: `mem_rd_addr → ex_rs1_addr`'s reset pin, which is the same
shape one stage over. The premise was wrong. The problem is not those
particular 64 pins; it is that the flush signal fans out to reset pins
across the whole pipeline, and removing one group promotes the next.

Worth noting how that was established: re-running the unmodified design
reproduced `−0.458 ns` exactly, to the digit, so Vivado is deterministic
here and the 1.8 MHz difference was a real regression rather than
place-and-route noise. The change was reverted — an optimisation that fails
its own justification is not worth the asymmetry it adds to the code.

**What both have in common.** Each assumed the tool had left something on
the table, and each was wrong in the same way: the design is not held back
by one slow path but by being broadly a little slow. 400 of 3,195 endpoints
miss, by about 0.19 ns each. That is a property of the whole placement, not
of any one path, and local edits just move which path happens to be last.

The honest conclusion is that 95.6 MHz is what this design does on this
part without a structural change. Making it meaningfully faster means
shortening the EX stage itself — resolving branches earlier, or splitting
the forward-then-compare chain across a pipeline stage — not persuading the
placer.

