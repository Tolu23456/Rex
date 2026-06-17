#include <stdio.h>
#include <time.h>
#include <stdlib.h>

static double elapsed_ns(struct timespec a, struct timespec b) {
    return (double)(b.tv_sec - a.tv_sec) * 1e9 + (double)(b.tv_nsec - a.tv_nsec);
}

int main(void) {
    const int iterations = 10000000;
    struct timespec t0, t1;
    
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < iterations; i++) {
        void *p = malloc(64);
        // Simulate some use
        ((int*)p)[0] = i;
        free(p);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    
    double total_ns = elapsed_ns(t0, t1);
    printf("C bench_arena: %.2f ns/op (%d ops in %.4f seconds)\n", 
           total_ns / iterations, iterations, total_ns / 1e9);
    printf("1\n");
    return 0;
}
