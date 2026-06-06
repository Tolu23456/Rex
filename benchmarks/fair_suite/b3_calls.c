#include <stdio.h>
#include <time.h>
#include <stdint.h>

static double elapsed_ms(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
}

// __attribute__((noinline)) ensures GCC -O3 does not constant-fold the loop
// away at compile time. Without it, the entire loop collapses to a single
// integer assignment, measuring nothing. noinline forces 200M real CALL/RET
// pairs so both languages measure actual calling-convention overhead.
__attribute__((noinline))
static int64_t increment(int64_t x) { return x + 1; }

int main(void) {
    struct timespec t0, t1;
    int64_t n = 0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int64_t i = 0; i < 200000000LL; i++) {
        n = increment(n);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("result=%lld  time=%.2f ms\n", (long long)n, elapsed_ms(t0, t1));
    return 0;
}
