/*
 *==========================================================================
 * link_c.ld - Memory layout for C programs
 *
 * Same split as link.ld: .text becomes the instruction memory image and
 * everything else becomes the data memory image, because the core is a
 * Harvard machine with two separate memories.
 *
 * What this adds over link.ld is everything a C program needs and an
 * assembly test does not: a stack, a zeroed .bss, a global pointer, and
 * somewhere for string literals to live.
 *==========================================================================
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS
{
    .text : {
        *(.text.init)           /* crt0 first: the core starts at address 0 */
        *(.text .text.*)
        . = ALIGN(4);
    } > IMEM

    /* String literals live here, and loads read them out of data memory. */
    .rodata : {
        . = ALIGN(4);
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        . = ALIGN(4);
    } > DMEM

    .data : {
        . = ALIGN(4);
        /* gp addresses a 4 KiB window with a 12-bit signed offset, so it is
           placed 2 KiB in, letting one gp-relative instruction reach the
           whole window. */
        __global_pointer$ = . + 0x800;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
    } > DMEM

    /* NOLOAD: .bss holds no data in the binary. crt0 writes the zeros. */
    .bss (NOLOAD) : {
        . = ALIGN(4);
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DMEM

    /* The stack grows downwards from the top of data memory. */
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);

    /DISCARD/ : {
        *(.comment)
        *(.note .note.*)
        *(.eh_frame .eh_frame.*)
        *(.riscv.attributes)
    }
}
