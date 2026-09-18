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

[ PASS ] fib             5386 cycles, 31 characters
[ PASS ] hello            169 cycles, 14 characters
[ PASS ] primes         13531 cycles, 59 characters
[ PASS ] sort            2656 cycles, 37 characters

 programs: 4/4 PASSED
```

```
$ make programs TB=primes

[ PASS ] primes         13531 cycles, 59 characters
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
- [ ] **Phase 4** — performance counters, CPI, synthesis + timing numbers
- [ ] **Phase 5** — block RAM inference, timing closure on Artix-7
- [ ] **Phase 6** — M / C / Zicsr extensions

## License

MIT — see [LICENSE](LICENSE).
