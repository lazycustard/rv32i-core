# rv32i-core

A 5-stage pipelined RISC-V **RV32I** processor written in Verilog, built
test-first: every module ships with a self-checking testbench, and nothing is
claimed to work until a test proves it.

> **Status: in progress.** This README tracks what is actually verified, not
> what is planned. The support table below is generated from the test suite,
> so it cannot drift from reality.

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
| ALU (register/immediate) | `add` `sub` `sll` `slt` `sltu` `xor` `srl` `sra` `or` `and` | ALU verified |
| Upper immediate | `lui` `auipc` | not yet |
| Jumps | `jal` `jalr` | not yet |
| Branches | `beq` `bne` `blt` `bge` `bltu` `bgeu` | not yet |
| Loads | `lb` `lh` `lw` `lbu` `lhu` | not yet |
| Stores | `sb` `sh` `sw` | not yet |
| System | `ecall` `ebreak` `fence` | not yet |

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

## Layout

```
rtl/        synthesizable RTL
tb/         self-checking testbenches (one per module)
tests/      assembly / C test programs
scripts/    build and test runners
docs/       diagrams and notes
sim/        build output (git-ignored)
```

## Roadmap

- [x] **Phase 0** — toolchain, test harness, CI
- [ ] **Phase 1** — complete and correct RV32I instruction set
- [ ] **Phase 2** — official [riscv-tests](https://github.com/riscv-software-src/riscv-tests) conformance suite
- [ ] **Phase 3** — run compiled C programs, UART output
- [ ] **Phase 4** — performance counters, CPI, synthesis + timing numbers
- [ ] **Phase 5** — block RAM inference, timing closure on Artix-7
- [ ] **Phase 6** — M / C / Zicsr extensions

## License

MIT — see [LICENSE](LICENSE).
