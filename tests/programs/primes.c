/*
 * Primes below 50 by trial division.
 *
 * The point is the division. RV32I has no divide instruction, so every
 * "%" here becomes a call to __umodsi3 in libgcc -- software division,
 * running on this core.
 */

#include "uart.h"

static int is_prime(unsigned int n)
{
    unsigned int d;

    if (n < 2u) {
        return 0;
    }
    for (d = 2u; d * d <= n; d++) {
        if (n % d == 0u) {
            return 0;
        }
    }
    return 1;
}

int main(void)
{
    unsigned int n;
    int count = 0;

    uart_puts("primes:");
    for (n = 2u; n < 50u; n++) {
        if (is_prime(n)) {
            uart_putc(' ');
            uart_put_uint(n);
            count++;
        }
    }
    uart_puts("\ncount: ");
    uart_put_int(count);
    uart_putc('\n');
    return 0;
}
