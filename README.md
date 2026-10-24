# rv32i-core

[![tests](https://github.com/lazycustard/rv32i-core/actions/workflows/ci.yml/badge.svg)](https://github.com/lazycustard/rv32i-core/actions/workflows/ci.yml)

A 5-stage pipelined RISC-V **RV32I** processor written in Verilog, built
test-first: every module ships with a self-checking testbench, and nothing is
claimed to work until a test proves it.

It passes **40 of 40** of the RISC-V project's own `rv32ui` conformance
tests, and runs **C compiled by GCC**, printing over a memory-mapped UART.

> **Status: in progress.** This README tracks what is actually verified, not
> what is planned. Nothing is marked working here until a test that would
> fail without it passes in CI.

## Quick start

Requires only [Icarus Verilog](https://steveicarus.github.io/iverilog/) — no
Vivado, no licences, no GUI.

```bash
# Linux
sudo apt-get install iverilog

# macOS
brew install icarus-verilog

# Windows
winget install --id Icarus.Verilog -e
```

Then:

```bash
make test               # run every self-checking testbench
make test TB=alu        # run one
make lint               # syntax and width checks, no simulation
make wave TB=alu        # open the waveform in GTKWave
make riscv-tests        # official conformance suite (needs RISC-V GCC)
make programs           # compile and run the C programs in tests/programs/
make synth              # Vivado: LUTs, Fmax, critical path (no board needed)
BP=0 make programs      # same, with the branch predictor disabled
```

No GNU Make? The runner is a plain shell script:

```bash
./scripts/run_tests.sh
```

Every testbench prints `RESULT: PASS` or `RESULT: FAIL` and the runner exits
non-zero on any failure, so this works unchanged in CI.

## Instruction support

| Group | Instructions | Status |
|---|---|---|
| ALU (register/immediate) | `add` `sub` `sll` `slt` `sltu` `xor` `srl` `sra` `or` `and` | verified in core |
| Upper immediate | `lui` `auipc` | verified in core |
| Jumps | `jal` `jalr` | verified in core |
| Branches | `beq` `bne` `blt` `bge` `bltu` `bgeu` | verified in core |
| Loads | `lb` `lh` `lw` `lbu` `lhu` | verified in core |
| Stores | `sb` `sh` `sw` | verified in core |
| System | `ecall` `ebreak` `fence` | decoded; traps are Phase 6 |

"Verified in core" means a program exercising that instruction runs through
the full pipeline and produces the expected architectural state — not merely
that the module decodes it.

## Conformance testing

Everything above is checked by tests written alongside the core, which is a
real limitation: if the specification was misread, the design and the test
inherit the same misreading and agree with each other. The suite can only
catch mistakes, not misunderstandings.

So the core is also run against the RISC-V project's own
[riscv-tests](https://github.com/riscv-software-src/riscv-tests) — test
vectors written by someone else, years before this core existed.

```bash
git submodule update --init --depth 1 tests/riscv-tests
make riscv-tests
```

This needs a RISC-V GCC toolchain (`gcc-riscv64-unknown-elf` on Ubuntu; see
`scripts/run_riscv_tests.sh` for other platforms). `make test` deliberately
does not, so the main suite still runs with nothing but Icarus installed.

### What is and is not standard here

The test sources in `tests/riscv-tests` are used **unmodified**. What is
replaced is the environment around them — `tests/env/riscv_test.h`.

The standard `p` environment is built on machine-mode CSRs: it installs a
trap vector with `csrw mtvec`, classifies traps by reading `mcause`, and
returns with `mret`. This core has no Zicsr extension yet, so none of those
instructions exist. The replacement reports results through `a0` and `ECALL`
instead:

```
a0 == 0   every test case passed
a0 != 0   a0 holds the number of the test case that failed
```

Two tests are skipped, for reasons recorded in the runner:

| Test | Why |
|---|---|
| `fence_i` | Needs Zifencei (self-modifying code); not part of the RV32I base |
| `ma_data` | Expects misaligned accesses to complete or trap. This core detects misalignment and refuses the access; trapping needs Zicsr |

So the honest claim is **the official instruction test vectors, under a
custom minimal environment** — not the full official `p` environment. Once
Zicsr lands in Phase 6, the standard environment can be used directly and
this caveat goes away.

### Results

**40 of 40 rv32ui tests pass**, 2 skipped for the reasons above.

```
riscv-tests rv32ui: 40/40 PASSED  (2 skipped)
```

| Group | Tests |
|---|---|
| Arithmetic | `add` `addi` `sub` |
| Logical | `and` `andi` `or` `ori` `xor` `xori` |
| Shifts | `sll` `slli` `srl` `srli` `sra` `srai` |
| Comparison | `slt` `slti` `sltiu` `sltu` |
| Branches | `beq` `bne` `blt` `bge` `bltu` `bgeu` |
| Jumps | `jal` `jalr` |
| Upper immediate | `lui` `auipc` |
| Loads | `lb` `lbu` `lh` `lhu` `lw` |
| Stores | `sb` `sh` `sw` |
| Mixed access | `ld_st` `st_ld` `simple` |

The suite was checked for teeth the same way the local one was: changing
`sra` to shift in zeros instead of the sign bit made `sra` and `srai` fail
and report `test case 3 failed`, while `srl` kept passing. `lui` failed too
— not a false positive, since the official LUI test uses `sra` to verify
sign extension:

```asm
TEST_CASE( 3, x1, 0xfffff800, lui x1, 0xfffff; sra x1,x1,1 );
```

## Running C programs

The core runs C compiled by GCC and prints through a memory-mapped UART:

```
$ make programs

[ PASS ] fib           4934 cyc, 4385 instr, CPI 1.12, 31 stall, 639 br (284 taken), 258 mispred
[ PASS ] hello         145 cyc, 119 instr, CPI 1.21, 14 stall, 29 br (14 taken), 5 mispred
[ PASS ] primes        11353 cyc, 9331 instr, CPI 1.21, 76 stall, 2892 br (1354 taken), 972 mispred
[ PASS ] sort          2314 cyc, 1854 instr, CPI 1.24, 92 stall, 470 br (227 taken), 183 mispred

 programs: 4/4 PASSED
```

```
$ make programs TB=primes

[ PASS ] primes        11353 cyc, 9331 instr, CPI 1.21, 76 stall, 2892 br (1354 taken), 972 mispred
           | primes: 2 3 5 7 11 13 17 19 23 29 31 37 41 43 47
           | count: 15
```

Each program in `tests/programs/` has an `.expected` file; the runner
compares what the core actually printed against it, so these are tests and
not just a demo.

| Program | What it exercises |
|---|---|
| `hello.c` | The UART, string literals in data memory |
| `fib.c` | Recursion — stack frames, saved return addresses, `jalr` |
| `sort.c` | Arrays, signed comparison (negative values sort correctly) |
| `primes.c` | Software division: RV32I has no divide, so `%` becomes a call to `__umodsi3` in libgcc |

The cycle counts above are with branch prediction on; see the Performance
section for the before-and-after.

### What it takes to run C

Three pieces, none of which the compiled C provides for itself:

**`tests/env/crt0.S`** — before `main()` can run, `sp` has to point at usable
memory, `gp` at the small-data window, and `.bss` has to be zeroed. `.bss`
occupies no space in the binary, so nothing loads those zeros; startup code
writes them.

**`tests/env/link_c.ld`** — adds a stack, `.bss` and `.rodata` to the
Harvard split. String literals live in data memory, which is where loads
read from.

**A UART, and an address decoder to reach it.** Until now the data memory
answered every address. A peripheral needs somewhere of its own:

```
0x1000_0000   UART transmit, write only   (low byte is sent)
0x1000_0004   UART status,   read only    (bit 0 = ready)
0x8000_0000   data memory
```

The status register is always ready, and software polls it anyway — that is
what a driver for real hardware has to do, and the register has to exist for
that code to be written against it. This is the core's first peripheral and
the beginning of a bus.

## Performance

The core counts cycles, retired instructions, stalls, branches and taken
branches in hardware. `mcycle` and `minstret` are 64 bits because that is
what the specification says they are; they become those CSRs when Zicsr
lands.

### Branch prediction: before and after

Branches dominated the cost. Every taken branch flushed two instructions,
because the core only learned where a branch went once it reached EX. A
64-entry branch target buffer with 2-bit direction counters now guesses in
the fetch stage, and EX checks the guess.

Two structures, added in that order:

- a **64-entry BTB** with 2-bit direction counters, which remembers where
  each branch PC went last time;
- an **8-entry return address stack**, because a BTB cannot predict a
  function return. The same `ret` instruction goes back to whichever call
  site invoked it, so "where it went last time" is the wrong question. A
  call pushes the address it will come back to, and a return pops it.

| Program | No prediction | + BTB | + RAS | CPI | Total saved |
|---|---|---|---|---|---|
| `hello` | 169 | 147 | **145** | 1.42 → **1.21** | 14.2% |
| `fib` | 5,386 | 4,994 | **4,934** | 1.22 → **1.12** | 8.4% |
| `sort` | 2,656 | 2,368 | **2,314** | 1.43 → **1.24** | 12.9% |
| `primes` | 13,531 | 11,531 | **11,353** | 1.45 → **1.21** | 16.1% |

| Program | Mispredicts before | After | Control transfers | Accuracy |
|---|---|---|---|---|
| `hello` | 17 | 5 | 32 | 84% |
| `fib` | 484 | 258 | 839 | 69% |
| `sort` | 354 | 183 | 597 | 69% |
| `primes` | 2,061 | 972 | 3,599 | 73% |

The "before" column is not remembered, it is reproducible: `BP_ENABLE=0`
pins the prediction to not-taken, which is exactly what the core did before
the predictor existed.

The return stack is updated in fetch, speculatively, rather than in EX once
the instruction is known to be real — and it has to be. Unwinding a
recursion is a run of returns with an instruction or two between them, so a
second return is fetched before the first reaches EX; updating in EX leaves
it reading a stale top of stack. Moving the update to fetch removed 88
mispredictions from `primes` alone.

The cost is that a mispredicted path can push or pop entries that should
never have existed, and there is no checkpoint to restore from. That is an
accuracy loss and nothing else: EX checks every prediction, so a drifted
stack produces a slower result, never a wrong one.

```bash
BP=0 make programs     # baseline
make programs          # with prediction
```

### Where the cycles go

Every cycle is accounted for by one identity:

```
cycles = instructions + stalls + 2 x mispredictions + pipeline fill
```

| Program | Predicted | Actual |
|---|---|---|
| `hello` | 119 + 14 + 2x5 + 2 = 145 | 145 |
| `fib` | 4385 + 31 + 2x258 + 2 = 4934 | 4934 |
| `sort` | 1854 + 92 + 2x183 + 2 = 2314 | 2314 |
| `primes` | 9331 + 76 + 2x972 + 2 = 11353 | 11353 |

Exact on all four, before and after. `program_tb.v` asserts this rather than
leaving it as an observation: if the pipeline's valid bit were wrong and
flushed instructions counted as retired, the residual would go negative and
CPI would quietly look better than the core is. Forcing the valid bit high
fails all four programs with `counter accounting is impossible`.

### What the numbers say

**Stalls were never the problem.** Load-use stalls are well under 1% of
cycles, so forwarding is doing its job and there is nothing to win there.

**`fib` still gains least, and that is informative.** The return stack
fixed its returns, but 69% accuracy means what remains is conditional
branches, not returns: recursive Fibonacci turns on `n < 2`, which
alternates in a pattern a per-branch 2-bit counter cannot learn. Neither a
bigger BTB nor a deeper stack helps there. It would take a history-based
predictor, one that correlates a branch with the outcomes of recent ones —
which is where this would go next.

**The return stack's depth turned out not to matter.** Raising it from 8 to
16 and then 32 changed nothing at all, which ruled out the obvious first
theory — that `fib`'s recursion was simply deeper than the stack. The
actual limit was *when* the stack was updated, not how big it was.

## Synthesis

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

### What synthesis caught that simulation could not

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

### The critical path

```
ex_rs1_addr → hazard unit comparator → forwarding mux
            → branch comparator → mispredict → id_pc reset pin
```

17 logic levels, 9 of them carry chains, and **60% of the delay is routing
rather than logic** — the design is spread out more than it is deep.

### An optimisation that did not work

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

## Design notes

**The ALU control field is 4 bits, not 3.** RV32I has ten distinct ALU
operations. Three bits encode eight, so a 3-bit field forces two operations to
share an encoding — which silently turns `or` into a shift, or `srl` into an
`and`. The encoding here is `{instr[30], funct3}`, which makes the R-type
decoder nearly free: `instr[30]` is exactly the bit that separates `add` from
`sub` and `srl` from `sra`.

**Branches do not reuse the ALU's zero flag.** Computing `a - b` and testing
for zero only ever implements `beq`. `blt` and `bltu` need signed and unsigned
comparisons that a zero flag cannot express, so branch decisions get a
dedicated comparator.

**LUI goes through the ALU as a pass-through** (`ALU_PASS_B`) rather than
needing an extra writeback source.

**Memory reads are asynchronous, for now.** That keeps the fetch and memory
stages simple while the pipeline control logic is being brought up. It also
means the memories infer distributed LUT RAM rather than block RAM, which
will not fit on an FPGA at any useful depth. Converting them to synchronous
reads is Phase 5 work and is flagged in the source.

## Layout

```
rtl/                 synthesizable RTL
tb/                  self-checking testbenches, one per module
tb/rv32i_asm.vh      assembler helpers, so test programs read as
                     rv_beq(1, 2, 8) rather than hand-encoded hex
tests/env/           linker script and result protocol for the official suite
tests/programs/      C programs with expected output, run as tests
tests/riscv-tests/   the official suite, as a submodule (unmodified)
tests/build/         compiled test programs (git-ignored)
scripts/             build and test runners
docs/                diagrams and notes
sim/                 simulation output (git-ignored)
```

## Roadmap

- [x] **Phase 0** — toolchain, test harness, CI
- [x] **Phase 1** — complete and correct RV32I instruction set
- [x] **Phase 2** — official [riscv-tests](https://github.com/riscv-software-src/riscv-tests) conformance suite
- [x] **Phase 3** — run compiled C programs, UART output
- [x] **Phase 4** — performance counters, CPI, branch prediction, synthesis numbers
- [ ] **Phase 5** — block RAM inference, timing closure on Artix-7
- [ ] **Phase 6** — M / C / Zicsr extensions

## License

MIT — see [LICENSE](LICENSE).
