/*
 *==========================================================================
 * link.ld - Memory layout for rv32i-core test programs
 *
 * The core is a Harvard machine: instructions and data live in physically
 * separate memories, each addressed from zero. A linker cannot place two
 * output sections at the same address, so the two regions are given
 * distinct addresses here and separated again at objcopy time -- .text
 * becomes the instruction memory image, everything else becomes the data
 * memory image.
 *
 * Data sits at 0x80000000, the conventional RISC-V RAM base. The core's
 * data memory decodes only the low address bits, so the high bits are
 * ignored and 0x80000000 lands at data word 0. A proper address decoder
 * arrives with the memory-mapped UART in Phase 3.
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
    /* Instruction memory. .text.init must come first: it holds _start,
       and the core begins executing at address 0 after reset. */
    .text : {
        *(.text.init)
        *(.text .text.*)
        . = ALIGN(4);
    } > IMEM

    /* Data memory. */
    .rodata : {
        . = ALIGN(4);
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > DMEM

    .data : {
        . = ALIGN(4);
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
    } > DMEM

    .bss : {
        . = ALIGN(4);
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
    } > DMEM

    /* Debug and metadata sections would otherwise end up in the objcopy
       output and confuse the hex conversion. */
    /DISCARD/ : {
        *(.comment)
        *(.note .note.*)
        *(.eh_frame .eh_frame.*)
        *(.riscv.attributes)
    }
}
