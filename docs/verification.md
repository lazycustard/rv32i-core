# Verification

How this core is checked, and what each layer of testing can and cannot
catch. See the [README](../README.md) for the summary.


## Why an outside test suite

Most of this core is checked by tests written alongside it — 432 of them,
one testbench per module plus whole programs through the pipeline. That is
a real limitation: if the specification was misread, the design and the
test inherit the same misreading and agree with each other. Tests written
beside a design can catch mistakes, not misunderstandings.

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

## What is and is not standard here

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

## Results

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

