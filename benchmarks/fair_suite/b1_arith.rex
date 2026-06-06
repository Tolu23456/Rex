// B1: Arithmetic Throughput
// 1 billion iterations of a 64-bit LCG: x = x * 1664525 + 1013904223
// O-Affine: Rex computes the closed-form via binary ladder at compile time.
// GCC -O3 cannot fold LCG modular exponentiation; runs all 1B iterations.
// Rex outputs: result on line 1, internal elapsed ms on line 2.

int :t0 = clock()
int :x = 1
for i in 0..1000000000:
    :x = x * 1664525
    :x = x + 1013904223
int :t1 = clock()
output x
output t1 - t0
