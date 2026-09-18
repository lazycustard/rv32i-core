/*
 * Recursive Fibonacci.
 *
 * Recursion is the real test here, not the arithmetic: every call has to
 * save the return address, push a frame, and come back through JALR. A
 * core without a working JALR cannot run this at all.
 */

#include "uart.h"

static int fib(int n)
{
    if (n < 2) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

int main(void)
{
    int i;

    uart_puts("fib:");
    for (i = 0; i <= 10; i++) {
        uart_putc(' ');
        uart_put_int(fib(i));
    }
    uart_putc('\n');
    return 0;
}
