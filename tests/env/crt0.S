/*
 *==========================================================================
 * crt0.S - C runtime startup
 *
 * A C program cannot simply be jumped into. Before main() runs, three
 * things must be true, and nothing in the compiled C does any of them:
 *
 *   1. sp points at usable memory. Every local variable, every saved
 *      register and every function call depends on it.
 *   2. gp points at the small-data area, if the compiler used gp-relative
 *      addressing for globals.
 *   3. .bss is zeroed. C guarantees that uninitialised globals start at
 *      zero, but .bss occupies no space in the binary -- there is nothing
 *      to load, so someone has to write the zeros at runtime.
 *
 * This file is that someone.
 *==========================================================================
 */

    .section .text.init
    .globl _start

_start:
    /* gp must be loaded without linker relaxation, since relaxation itself
       is what would rewrite this instruction to be gp-relative. */
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    la      sp, _stack_top

    /* Zero .bss, one word at a time. Both symbols are word aligned by the
       linker script, so no partial word is possible. */
    la      t0, _bss_start
    la      t1, _bss_end
1:
    bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:

    /* Hand over to C. "call" expands to auipc + jalr, so getting here at
       all already proves JALR works. */
    call    main

    /* main returned. Report completion the same way the test suite does:
       a0 = 0 means success, and ECALL is the halt signal the testbench
       watches for. The loop after it matters because this core does not
       trap on ECALL -- without it the PC would simply run on. */
    li      a0, 0
    ecall
3:
    j       3b
