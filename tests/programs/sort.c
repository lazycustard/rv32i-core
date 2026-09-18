/*
 * Bubble sort over an array of signed values.
 *
 * Exercises array indexing, loads and stores, and signed comparison --
 * the negative entries would sort to the wrong end if BLT were decided
 * by an unsigned comparison.
 */

#include "uart.h"

static void sort(int *a, int n)
{
    int i, j, t;

    for (i = 0; i < n - 1; i++) {
        for (j = 0; j < n - 1 - i; j++) {
            if (a[j] > a[j + 1]) {
                t        = a[j];
                a[j]     = a[j + 1];
                a[j + 1] = t;
            }
        }
    }
}

int main(void)
{
    int data[] = { 42, -7, 13, 0, 99, -100, 5, 77, 1, 23 };
    int n = 10;
    int i;

    sort(data, n);

    uart_puts("sorted:");
    for (i = 0; i < n; i++) {
        uart_putc(' ');
        uart_put_int(data[i]);
    }
    uart_putc('\n');
    return 0;
}
