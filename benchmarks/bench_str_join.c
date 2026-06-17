#include <stdio.h>
#include <time.h>
#include <string.h>
#include <stdlib.h>

static double elapsed_ns(struct timespec a, struct timespec b) {
    return (double)(b.tv_sec - a.tv_sec) * 1e9 + (double)(b.tv_nsec - a.tv_nsec);
}

int main(void) {
    const char *word = "word ";
    size_t word_len = strlen(word);
    char *long_str = malloc(1001 * word_len + 1);
    long_str[0] = '\0';
    for (int i = 0; i < 1000; i++) {
        strcat(long_str, word);
    }
    
    const int iterations = 1000;
    struct timespec t0, t1;
    
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int j = 0; j < iterations; j++) {
        // C implementation of split/join
        char *s = strdup(long_str);
        char **parts = malloc(1001 * sizeof(char*));
        int count = 0;
        char *token = strtok(s, " ");
        while (token) {
            parts[count++] = strdup(token);
            token = strtok(NULL, " ");
        }
        
        size_t total_len = 0;
        for (int i = 0; i < count; i++) {
            total_len += strlen(parts[i]);
        }
        total_len += (count > 0 ? count - 1 : 0);
        char *joined = malloc(total_len + 1);
        joined[0] = '\0';
        for (int i = 0; i < count; i++) {
            strcat(joined, parts[i]);
            if (i < count - 1) strcat(joined, "-");
        }
        
        free(joined);
        for (int i = 0; i < count; i++) free(parts[i]);
        free(parts);
        free(s);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    
    double total_ns = elapsed_ns(t0, t1);
    printf("C bench_str_join: %.2f ns/op (%d ops in %.4f seconds)\n", 
           total_ns / iterations, iterations, total_ns / 1e9);
    printf("1\n");
    
    free(long_str);
    return 0;
}
