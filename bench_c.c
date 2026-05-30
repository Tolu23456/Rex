#include <stdio.h>
int main() {
    long total = 0;
    for (long i = 0; i < 10000000; i++) {
        total += i;
    }
    printf("%ld\n", total);
    return 0;
}
