#include <stdio.h>
#include <time.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define ALLOCS 500000
#define BLOCK  80

static double ns(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec);
}

int main(void) {
    struct timespec t0, t1;
    void *ptrs[ALLOCS];

    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < ALLOCS; i++) {
        ptrs[i] = malloc(BLOCK);
        ((char *)ptrs[i])[0] = (char)i;
    }
    for (int i = 0; i < ALLOCS; i++) free(ptrs[i]);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    printf("malloc/free x%d (%d bytes each)  time=%.2f ms\n",
           ALLOCS, BLOCK, ns(t0, t1) / 1e6);
    return 0;
}
