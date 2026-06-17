#include <stdio.h>
#include <time.h>
#include <stdlib.h>
#include <stdint.h>

static double elapsed_ns(struct timespec a, struct timespec b) {
    return (double)(b.tv_sec - a.tv_sec) * 1e9 + (double)(b.tv_nsec - a.tv_nsec);
}

int compare_ints(const void *a, const void *b) {
    return (*(int64_t*)a - *(int64_t*)b);
}

int main(void) {
    struct timespec t0, t1;
    const int64_t n = 1000000LL;
    int64_t *data = malloc(n * sizeof(int64_t));
    
    int64_t seed = 12345;
    for (int64_t i = 0; i < n; i++) {
        seed = (seed * 1103515245LL + 12345LL) % 2147483648LL;
        data[i] = seed;
    }
    
    clock_gettime(CLOCK_MONOTONIC, &t0);
    qsort(data, n, sizeof(int64_t), compare_ints);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    
    double total_ns = elapsed_ns(t0, t1);
    printf("C bench_seq_sort: %.2f ns/op (%lld ops in %.4f seconds)\n", 
           total_ns / n, n, total_ns / 1e9);
    printf("%lld\n", n);
    
    free(data);
    return 0;
}
