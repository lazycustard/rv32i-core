# rv32i-core

[![tests](https://github.com/lazycustard/rv32i-core/actions/workflows/ci.yml/badge.svg)](https://github.com/lazycustard/rv32i-core/actions/workflows/ci.yml)

A 5-stage pipelined RISC-V **RV32I** processor written in Verilog, built
test-first: every module ships with a self-checking testbench, and nothing is
claimed to work until a test proves it.

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

Not yet run — the toolchain is still being set up. This section will carry
the per-test table once it has actually executed, and not before.

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
tests/riscv-tests/   the official suite, as a submodule (unmodified)
tests/build/         compiled test programs (git-ignored)
scripts/             build and test runners
docs/                diagrams and notes
sim/                 simulation output (git-ignored)
```

## Roadmap

- [x] **Phase 0** — toolchain, test harness, CI
- [x] **Phase 1** — complete and correct RV32I instruction set
- [ ] **Phase 2** — official [riscv-tests](https://github.com/riscv-software-src/riscv-tests) conformance suite
- [ ] **Phase 3** — run compiled C programs, UART output
- [ ] **Phase 4** — performance counters, CPI, synthesis + timing numbers
- [ ] **Phase 5** — block RAM inference, timing closure on Artix-7
- [ ] **Phase 6** — M / C / Zicsr extensions

## License

MIT — see [LICENSE](LICENSE).
