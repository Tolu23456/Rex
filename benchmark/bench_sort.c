#include <stdio.h>
#include <time.h>
#include <stdint.h>
#include <string.h>

#define N 20000

static double ns(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec);
}

static int64_t arr[N];

static void bubble_sort(int64_t *a, int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (a[j] > a[j+1]) {
                int64_t t = a[j]; a[j] = a[j+1]; a[j+1] = t;
            }
        }
    }
}

int main(void) {
    struct timespec t0, t1;
    for (int i = 0; i < N; i++) arr[i] = (int64_t)(N - i);

    clock_gettime(CLOCK_MONOTONIC, &t0);
    bubble_sort(arr, N);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    printf("sorted[0]=%lld sorted[N-1]=%lld  time=%.2f ms\n",
           (long long)arr[0], (long long)arr[N-1], ns(t0, t1) / 1e6);
    return 0;
}
