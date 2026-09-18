/*
 *==========================================================================
 * uart.h - Minimal output for programs running on the core
 *
 * There is no C library here, so printing is written from scratch against
 * the memory-mapped UART:
 *
 *   0x1000_0000  transmit, write only  -- the low byte is sent
 *   0x1000_0004  status,   read only   -- bit 0 set means ready
 *
 * volatile matters on both. Without it the compiler is entitled to hoist
 * the status read out of the polling loop (nothing in the C language says
 * that value can change on its own) and to drop repeated writes to the
 * transmit register as dead stores.
 *==========================================================================
 */

#ifndef UART_H
#define UART_H

#define UART_BASE   0x10000000u
#define UART_TX     (*(volatile unsigned int *)(UART_BASE + 0u))
#define UART_STATUS (*(volatile unsigned int *)(UART_BASE + 4u))

static void uart_putc(char c)
{
    while ((UART_STATUS & 1u) == 0u) {
        /* wait for the transmitter */
    }
    UART_TX = (unsigned int)(unsigned char)c;
}

static void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s++);
    }
}

static void uart_put_uint(unsigned int v)
{
    char buf[12];
    int  i = 0;

    if (v == 0u) {
        uart_putc('0');
        return;
    }

    /* Digits come out least significant first, so they are buffered and
       printed in reverse.

       Note that "/ 10" and "% 10" are not single instructions here: RV32I
       has no divide, so the compiler emits calls to __udivsi3 and
       __umodsi3 from libgcc. Software division is the price of leaving the
       M extension out of the base ISA. */
    while (v != 0u) {
        buf[i++] = (char)('0' + (v % 10u));
        v /= 10u;
    }

    while (i > 0) {
        uart_putc(buf[--i]);
    }
}

static void uart_put_int(int v)
{
    if (v < 0) {
        uart_putc('-');
        uart_put_uint((unsigned int)(-(long)v));
    } else {
        uart_put_uint((unsigned int)v);
    }
}

static void uart_put_hex(unsigned int v)
{
    const char *digits = "0123456789abcdef";
    int i;

    uart_puts("0x");
    for (i = 28; i >= 0; i -= 4) {
        uart_putc(digits[(v >> i) & 0xfu]);
    }
}

#endif
