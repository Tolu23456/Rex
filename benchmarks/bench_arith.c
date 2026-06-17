#include <stdio.h>
#include <time.h>
#include <stdint.h>

static double elapsed_ns(struct timespec a, struct timespec b) {
    return (double)(b.tv_sec - a.tv_sec) * 1e9 + (double)(b.tv_nsec - a.tv_nsec);
}

int main(void) {
    struct timespec t0, t1;
    int64_t sum = 0;
    const int64_t iterations = 2000000000LL;
    
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int64_t i = 0; i < iterations; i++) {
        sum = sum + i * 3 - i / 7 + i % 13;
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    
    double total_ns = elapsed_ns(t0, t1);
    printf("C bench_arith: %.2f ns/op (%lld ops in %.4f seconds)\n", 
           total_ns / iterations, iterations, total_ns / 1e9);
    printf("%lld\n", (long long)sum);
    return 0;
}
