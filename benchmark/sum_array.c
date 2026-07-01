#include <stdio.h>
#include <stdlib.h>

long sum_array(long *arr, long n) {
    long sum = 0;
    for (long i = 0; i < n; i++) {
        sum += arr[i];
    }
    return sum;
}

int main(int argc, char **argv) {
    long n = atol(argv[1]);
    long *arr = malloc(n * sizeof(long));
    for (long i = 0; i < n; i++) arr[i] = i;
    long result = sum_array(arr, n);
    printf("%ld\n", result);
    free(arr);
    return 0;
}
