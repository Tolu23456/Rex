// B1: Arithmetic Throughput
// 1 billion iterations of a 64-bit LCG: x = x * 1664525 + 1013904223
// Result is printed to prevent dead-code elimination.

int :x = 1
for :i in 0..1000000000:
    :x = x * 1664525
    :x = x + 1013904223
output x
