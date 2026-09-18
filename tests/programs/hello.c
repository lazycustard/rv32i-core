/*
 * The first C program to run on this core.
 */

#include "uart.h"

int main(void)
{
    uart_puts("Hello, World!\n");
    return 0;
}
