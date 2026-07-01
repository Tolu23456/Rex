#include <stdio.h>

long fib(int n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int main() {
    long sum = 0;
    for (int i = 0; i < 10000000; i++) {
        sum += fib(20);
    }
    printf("%ld\n", sum);
    return 0;
}
