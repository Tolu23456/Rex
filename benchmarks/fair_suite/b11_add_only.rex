// B11: Add-only constant folding — 1 billion iterations of x = x+7
// O-Affine-Add: computes B*N = 7,000,000,000 at compile time; emits
// a single add instruction. GCC -O3 also folds this loop.
// Both eliminate the loop; this benchmark confirms compiler parity.
// Rex outputs: result on line 1, internal elapsed ms on line 2.

int :t0 = clock()
int :x = 1
for i in 0..1000000000:
    :x = x + 7
int :t1 = clock()
output x
output t1 - t0
