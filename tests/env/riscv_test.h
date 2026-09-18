/*
 *==========================================================================
 * riscv_test.h - Minimal test environment for rv32i-core
 *
 * The official riscv-tests suite separates WHAT is tested (isa/rv32ui/*.S,
 * written by the RISC-V project) from the ENVIRONMENT that starts a test up
 * and reports its result (env/p/riscv_test.h). The test sources are used
 * here unmodified; only the environment is replaced.
 *
 * It has to be replaced because the standard "p" environment is built on
 * machine-mode CSRs: it installs a trap vector with "csrw mtvec", reads
 * "mcause" to classify traps, and returns with "mret". This core does not
 * implement the Zicsr extension yet -- that is Phase 6 -- so none of those
 * instructions exist.
 *
 * What is lost by doing this: the trap-based parts of the suite, and the
 * claim of running the full official "p" environment. What is kept: every
 * instruction test vector, written by an authority other than whoever wrote
 * this core -- which is the entire point of running the suite at all.
 *
 * Result protocol, replacing the tohost memory handshake:
 *
 *     a0 == 0   every test case passed
 *     a0 != 0   a0 holds the number of the test case that failed
 *
 * signalled by ECALL, which the core reports on dbg_ecall_o.
 *==========================================================================
 */

#ifndef RV32I_CORE_TEST_H
#define RV32I_CORE_TEST_H

/*
 * Mode-selection macros. The standard environment uses these to configure
 * privilege levels and extensions. This core is machine mode only with no
 * CSRs, so there is nothing to configure.
 */
#define RVTEST_RV32U
#define RVTEST_RV64U    RVTEST_RV32U
#define RVTEST_RV32M
#define RVTEST_RV64M    RVTEST_RV32M
#define RVTEST_RV32S
#define RVTEST_RV64S    RVTEST_RV32S

/* The test macros track the current test case number in gp. */
#define TESTNUM gp

/*
 * Entry point. The reset vector is address 0, and .text.init is placed
 * there by the linker script, so execution simply begins at _start.
 */
#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .globl _start;                                                  \
_start:                                                                 \
        li TESTNUM, 0;

#define RVTEST_CODE_END

/*
 * Pass and fail both end in ECALL followed by a self-loop. The loop
 * matters: this core does not trap on ECALL, so without it the program
 * counter would run on into whatever follows.
 */
#define RVTEST_PASS                                                     \
        li a0, 0;                                                       \
        ecall;                                                          \
1:      j 1b;

#define RVTEST_FAIL                                                     \
        addi a0, TESTNUM, 0;                                            \
        ecall;                                                          \
1:      j 1b;

/*
 * The signature symbols are kept so the test sources assemble unchanged.
 * There is no tohost/fromhost block: the result travels in a0, not through
 * memory.
 */
#define RVTEST_DATA_BEGIN                                               \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END                                                 \
        .align 4; .global end_signature; end_signature:

#endif
