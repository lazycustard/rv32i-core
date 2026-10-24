# Running compiled C

What a C program needs before it can run on this core.
See the [README](../README.md) for the summary.

## What it takes to run C

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

