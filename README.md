# rv32i-core

[![tests](https://github.com/lazycustard/rv32i-core/actions/workflows/ci.yml/badge.svg)](https://github.com/lazycustard/rv32i-core/actions/workflows/ci.yml)

A 5-stage pipelined RISC-V **RV32I** processor in Verilog, written from
scratch and built test-first.

| | |
|---|---|
| Correctness | **40/40** official [riscv-tests](https://github.com/riscv-software-src/riscv-tests), plus 432 local checks |
| Software | Runs **C compiled by GCC**, printing over a memory-mapped UART |
| Performance | **CPI 1.45 → 1.21** with branch prediction and a return address stack |
| Hardware | **1,642 LUTs at 95.6 MHz** on Artix-7 (`xc7a35t`) |

Everything above is reproducible from this repository. Nothing is claimed
here that a command in the next section does not demonstrate.

## Quick start

`make test` needs only [Icarus Verilog](https://steveicarus.github.io/iverilog/)
— no licences, no GUI.

```bash
sudo apt-get install iverilog          # Linux
brew install icarus-verilog            # macOS
winget install --id Icarus.Verilog -e  # Windows
```

```bash
make test               # 432 self-checking checks across 11 testbenches
make lint               # syntax and width checks, no simulation
make wave TB=alu        # open a waveform in GTKWave

make riscv-tests        # the official conformance suite  (needs RISC-V GCC)
make programs           # compile and run C programs      (needs RISC-V GCC)
make synth              # LUTs, Fmax, critical path       (needs Vivado)
make gui                # look at the routed design
```

No GNU Make? Every target is a plain shell script in `scripts/`.

## What it runs

```
$ make programs TB=primes

[ PASS ] primes   11353 cyc, 9331 instr, CPI 1.21, 76 stall, 2892 br (1354 taken), 972 mispred
           | primes: 2 3 5 7 11 13 17 19 23 29 31 37 41 43 47
           | count: 15
```

That is C source, compiled by GCC, executing on this core and printing
through its UART. Each program in `tests/programs/` has an `.expected`
file, so these are tests rather than a demo.

| Program | What it exercises |
|---|---|
| `hello.c` | The UART, string literals in data memory |
| `fib.c` | Recursion — stack frames, return addresses, `jalr` |
| `sort.c` | Arrays, signed comparison |
| `primes.c` | Software division: RV32I has no divide instruction |

## Instruction support

| Group | Instructions |
|---|---|
| ALU | `add` `sub` `sll` `slt` `sltu` `xor` `srl` `sra` `or` `and` + immediates |
| Upper immediate | `lui` `auipc` |
| Jumps | `jal` `jalr` |
| Branches | `beq` `bne` `blt` `bge` `bltu` `bgeu` |
| Loads | `lb` `lh` `lw` `lbu` `lhu` |
| Stores | `sb` `sh` `sw` |
| System | `ecall` `ebreak` `fence` — decoded; traps are Phase 6 |

All of it verified in the core: a program exercising the instruction runs
through the full pipeline and produces the expected architectural state.

## Design notes

**The ALU control field is 4 bits, not 3.** RV32I has ten ALU operations
and three bits encode eight, so a 3-bit field forces two to share an
encoding — silently turning `or` into a shift. The encoding is
`{instr[30], funct3}`, which makes the R-type decoder nearly free.

**Branches do not reuse the ALU's zero flag.** Computing `a - b` and
testing for zero only ever implements `beq`; `blt` and `bltu` need signed
and unsigned comparisons a zero flag cannot express.

**A flushed pipeline slot carries NOP, not zero.** The all-zero word is not
a no-op in RV32I — opcode `0000000` is undefined — so zeroing a slot would
raise an illegal instruction on every taken branch.

**The memories live outside the core.** With them inside, the program was a
compile-time constant and synthesis folded the entire pipeline into three
LUTs — and there was no way to load a program on real hardware either.
`rv32i_core` is the pipeline; `rv32i_soc` adds the memories.

**Memory reads are still asynchronous.** That keeps the fetch and memory
stages simple, but infers distributed LUT RAM rather than block RAM.
Converting them is Phase 5 and is flagged in the source.

## Going deeper

| | |
|---|---|
| [docs/verification.md](docs/verification.md) | How the core is tested, and what each layer can and cannot catch |
| [docs/performance.md](docs/performance.md) | Where the cycles go; branch prediction before and after |
| [docs/synthesis.md](docs/synthesis.md) | FPGA cost, the critical path, and two optimisations that failed |
| [docs/software.md](docs/software.md) | What a C program needs before it can run |

## Layout

```
rtl/                 synthesizable RTL
rtl/rv32i_core.v     the pipeline; memory through ports
rtl/rv32i_soc.v      core + instruction and data memory
tb/                  self-checking testbenches, one per module
tb/rv32i_asm.vh      assembler helpers, so tests read as rv_beq(1, 2, 8)
tests/env/           linker scripts, startup code, UART driver
tests/programs/      C programs with expected output
tests/riscv-tests/   the official suite, as a submodule (unmodified)
scripts/             build and test runners
constraints/         timing constraints for synthesis
```

## Roadmap

- [x] **Phase 0** — toolchain, test harness, CI
- [x] **Phase 1** — complete and correct RV32I instruction set
- [x] **Phase 2** — official riscv-tests conformance suite
- [x] **Phase 3** — compiled C programs, UART output
- [x] **Phase 4** — performance counters, branch prediction, synthesis numbers
- [ ] **Phase 5** — block RAM inference, timing closure
- [ ] **Phase 6** — M / C / Zicsr extensions

## License

MIT — see [LICENSE](LICENSE).
