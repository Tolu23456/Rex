#include <stdio.h>
#include <time.h>
#include <stdlib.h>
#include <stdint.h>

static double elapsed_ns(struct timespec a, struct timespec b) {
    return (double)(b.tv_sec - a.tv_sec) * 1e9 + (double)(b.tv_nsec - a.tv_nsec);
}

int main(void) {
    struct timespec t0, t1;
    const int64_t iterations = 10000000LL;
    
    clock_gettime(CLOCK_MONOTONIC, &t0);
    
    int64_t *data = malloc(8 * sizeof(int64_t));
    int64_t cap = 8;
    int64_t len = 0;
    
    for (int64_t i = 0; i < iterations; i++) {
        if (len == cap) {
            cap *= 2;
            data = realloc(data, cap * sizeof(int64_t));
        }
        data[len++] = i;
    }
    
    for (int64_t i = 0; i < iterations; i++) {
        len--;
    }
    
    free(data);
    
    clock_gettime(CLOCK_MONOTONIC, &t1);
    
    double total_ns = elapsed_ns(t0, t1);
    printf("C bench_seq_push: %.2f ns/op (%lld ops in %.4f seconds)\n", 
           total_ns / iterations, iterations, total_ns / 1e9);
    printf("1\n");
    return 0;
}
