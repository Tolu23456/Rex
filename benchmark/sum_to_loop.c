#include <stdio.h>

long sum_to(int n) {
    long s = 0;
    for (int i = 0; i < n; i++) {
        s += i;
    }
    return s;
}

int main() {
    long x = 0;
    for (int i = 0; i < 1000000; i++) {
        x += sum_to(1000);
    }
    printf("%ld\n", x);
    return 0;
}
