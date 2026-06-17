#include <stdio.h>
#include <time.h>
#include <stdlib.h>
#include <stdint.h>
#include "uthash.h" // Assuming uthash.h is available or we use a simple open-addressing map

static double elapsed_ns(struct timespec a, struct timespec b) {
    return (double)(b.tv_sec - a.tv_sec) * 1e9 + (double)(b.tv_nsec - a.tv_nsec);
}

typedef struct {
    int64_t key;
    int64_t value;
    UT_hash_handle hh;
} entry_t;

int main(void) {
    entry_t *map = NULL;
    const int iterations = 1000000;
    struct timespec t0, t1;
    
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int64_t i = 0; i < iterations; i++) {
        entry_t *e = malloc(sizeof(entry_t));
        e->key = i;
        e->value = i * 2;
        HASH_ADD_INT(map, key, e);
    }
    
    int64_t sum = 0;
    for (int64_t j = 0; j < iterations; j++) {
        entry_t *e;
        HASH_FIND_INT(map, &j, e);
        if (e) sum += e->value;
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    
    double total_ns = elapsed_ns(t0, t1);
    printf("C bench_dict: %.2f ns/op (%d ops in %.4f seconds)\n", 
           total_ns / iterations, iterations, total_ns / 1e9);
    printf("%lld\n", (long long)sum);
    
    entry_t *curr, *tmp;
    HASH_ITER(hh, map, curr, tmp) {
        HASH_DEL(map, curr);
        free(curr);
    }
    return 0;
}
