#include <stdio.h>

int main() {
    long sum = 0;
    for (long i = 0; i < 100000000; i++) {
        sum += i;
    }
    printf("%ld\n", sum);
    return 0;
}
