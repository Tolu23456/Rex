#include <stdio.h>
#include <time.h>
#include <stdint.h>
#include <stdlib.h>

static double elapsed_ms(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
}

int main(void) {
    struct timespec t0, t1;

    // Identical growth strategy to Rex seq: start at cap=8, double on overflow.
    int64_t cap = 8;
    int64_t len = 0;
    int64_t *data = malloc((size_t)cap * sizeof(int64_t));

    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int64_t i = 0; i < 1000000LL; i++) {
        if (len == cap) {
            cap *= 2;
            data = realloc(data, (size_t)cap * sizeof(int64_t));
        }
        data[len++] = i;
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);

    printf("len=%lld last=%lld  time=%.2f ms\n",
           (long long)len, (long long)data[len - 1], elapsed_ms(t0, t1));
    free(data);
    return 0;
}
