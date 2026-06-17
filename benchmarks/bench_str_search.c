#include <stdio.h>
#include <time.h>
#include <string.h>
#include <stdlib.h>

static double elapsed_ns(struct timespec a, struct timespec b) {
    return (double)(b.tv_sec - a.tv_sec) * 1e9 + (double)(b.tv_nsec - a.tv_nsec);
}

int main(void) {
    const char *base = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    size_t base_len = strlen(base);
    size_t haystack_len = base_len;
    char *haystack = strdup(base);
    
    for (int i = 0; i < 7; i++) {
        char *new_h = malloc(haystack_len * 2 + 1);
        memcpy(new_h, haystack, haystack_len);
        memcpy(new_h + haystack_len, haystack, haystack_len);
        new_h[haystack_len * 2] = '\0';
        free(haystack);
        haystack = new_h;
        haystack_len *= 2;
    }
    
    const char *needle = "XYZ0";
    const int iterations = 100000;
    int count = 0;
    struct timespec t0, t1;
    
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int j = 0; j < iterations; j++) {
        if (strstr(haystack, needle)) {
            count++;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    
    double total_ns = elapsed_ns(t0, t1);
    printf("C bench_str_search: %.2f ns/op (%d ops in %.4f seconds)\n", 
           total_ns / iterations, iterations, total_ns / 1e9);
    printf("%d\n", count);
    
    free(haystack);
    return 0;
}
