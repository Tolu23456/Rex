#include <stdio.h>
#include <time.h>
#include <stdint.h>

static double ns(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec);
}

int main(void) {
    struct timespec t0, t1;
    volatile int64_t sum = 0;
    const int64_t N = 1000000000LL;

    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int64_t i = 1; i <= N; i++) sum += i;
    clock_gettime(CLOCK_MONOTONIC, &t1);

    printf("sum=%lld  time=%.2f ms\n", (long long)sum, ns(t0, t1) / 1e6);
    return 0;
}
