#include <stdio.h>
#include <time.h>
#include <stdint.h>

static double elapsed_ms(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
}

// __attribute__((noinline)) prevents GCC -O3 from seeing through the loop and
// constant-folding modular exponentiation. Without it, GCC would not eliminate
// the loop (non-power-of-2 multiplier), but we keep the function boundary to
// ensure an apples-to-apples comparison with Rex which folds via binary ladder.
__attribute__((noinline))
static int64_t mul_fold(int64_t x, int64_t a, int64_t n) {
    for (int64_t i = 0; i < n; i++) x *= a;
    return x;
}

int main(void) {
    struct timespec t0, t1;
    const int64_t A = 6364136223846793005LL;  // PCG-XSH-RR 64-bit multiplier
    clock_gettime(CLOCK_MONOTONIC, &t0);
    int64_t result = mul_fold(1LL, A, 1000000000LL);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("result=%lld  time=%.2f ms\n", (long long)result, elapsed_ms(t0, t1));
    return 0;
}
