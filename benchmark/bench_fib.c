#include <stdio.h>
#include <time.h>
#include <stdint.h>

static double ns(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec);
}

static int64_t fib(int64_t n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    int64_t result = fib(42);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    printf("fib(42)=%lld  time=%.2f ms\n", (long long)result, ns(t0, t1) / 1e6);
    return 0;
}
