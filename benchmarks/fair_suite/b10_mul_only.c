#include <stdio.h>
#include <time.h>
#include <stdint.h>

static double elapsed_ms(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
}

int main(void) {
    struct timespec t0, t1;
    int64_t x = 1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int64_t i = 0; i < 1000000000LL; i++)
        x = x * 3;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("result=%lld  time=%.2f ms\n", (long long)x, elapsed_ms(t0, t1));
    return 0;
}
