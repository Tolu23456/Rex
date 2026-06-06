#include <stdio.h>
#include <time.h>
#include <stdint.h>

static double elapsed_ms(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
}

int main(void) {
    struct timespec t0, t1;
    int64_t sum = 0, a, b, r;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int64_t k = 0; k < 1000000LL; k++) {
        a = k * 1234567LL + 7654321LL;
        b = k * 891011LL  + 1213141LL;
        while (b != 0) { r = a % b; a = b; b = r; }
        sum += a;
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("result=%lld  time=%.2f ms\n", (long long)sum, elapsed_ms(t0, t1));
    return 0;
}
