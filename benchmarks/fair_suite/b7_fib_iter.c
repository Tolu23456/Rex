#include <stdio.h>
#include <time.h>
#include <stdint.h>

static double elapsed_ms(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
}

int main(void) {
    struct timespec t0, t1;
    int64_t a, b, c;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int64_t rep = 0; rep < 10000000LL; rep++) {
        a = 0; b = 1;
        for (int j = 0; j < 80; j++) {
            c = a + b; a = b; b = c;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("fib(80)=%lld  time=%.2f ms\n", (long long)b, elapsed_ms(t0, t1));
    return 0;
}
